import '../../domain/exceptions.dart';
import '../../domain/ids.dart';
import '../models/models.dart';
import '../storage/app_storage.dart';

class UserRepository {
  UserRepository(this._storage);
  final AppStorage _storage;

  static const String _table = 'users';

  /// A login PIN is 4 to 8 digits, matching the admin settings form.
  static final RegExp _pinPattern = RegExp(r'^\d{4,8}$');

  static bool isValidPin(String pin) => _pinPattern.hasMatch(pin);

  Future<void> seedDefaults() async {
    if ((await all()).isEmpty) {
      await create(name: 'Admin', pin: '1234', role: UserRole.admin);
      await create(name: 'Staff', pin: '1111', role: UserRole.staff);
    }
  }

  Future<User> create({
    required String name,
    required String pin,
    required UserRole role,
    bool active = true,
    String email = '',
  }) async {
    final cleanName = name.trim();
    final cleanPin = pin.trim();
    _checkFormat(cleanName, cleanPin);
    await _checkPinFree(cleanPin);
    final user = User(
      id: newId('usr'),
      name: cleanName,
      pin: cleanPin,
      role: role,
      active: active,
      email: email,
    );
    await _storage.insert(_table, user.toMap());
    return user;
  }

  Future<List<User>> all() async =>
      (await _storage.find(_table, orderBy: 'name')).map(User.fromMap).toList();

  Future<User?> findById(String id) async {
    final m = await _storage.findOne(_table, {'id': id});
    return m == null ? null : User.fromMap(m);
  }

  Future<User> loginByPin(String pin) async {
    final matches = [
      for (final u in await all())
        if (u.pin == pin) u,
    ];
    if (matches.isEmpty) throw const ValidationException('Wrong PIN');
    // Older databases could already hold a duplicate PIN because the previous
    // PIN editor did not check. Pick an active account so the office is never
    // locked out; Admin Settings flags the duplicate for the admin to fix.
    final active = [
      for (final u in matches)
        if (u.active) u,
    ];
    if (active.isEmpty) {
      throw const PermissionDeniedException('User is deactivated');
    }
    return active.first;
  }

  Future<void> update(User user) async {
    final cleanName = user.name.trim();
    final cleanPin = user.pin.trim();
    _checkFormat(cleanName, cleanPin);
    final existing = await findById(user.id);
    if (existing == null || existing.pin != cleanPin) {
      // Only check when the PIN changes. An older database may already hold a
      // duplicate from before this rule; updating that user's other fields must
      // still work so the admin can correct the PIN.
      await _checkPinFree(cleanPin, exceptUserId: user.id);
    }
    // An admin screen may have loaded the account before a sign-in happened on
    // another terminal. Never move the stored time backwards.
    final previousLogin = existing?.lastLoginAt;
    final incomingLogin = user.lastLoginAt;
    final lastLoginAt =
        previousLogin != null &&
            (incomingLogin == null || previousLogin > incomingLogin)
        ? previousLogin
        : incomingLogin;
    await _storage.update(
      _table,
      {'id': user.id},
      user
          .copyWith(name: cleanName, pin: cleanPin, lastLoginAt: lastLoginAt)
          .toMap(),
    );
  }

  /// Records a successful sign-in without touching the rest of the account, so
  /// a concurrent edit elsewhere is not overwritten.
  Future<void> markLogin(String userId, int at) async {
    await _storage.update(_table, {'id': userId}, {'last_login_at': at});
  }

  static void _checkFormat(String name, String pin) {
    if (name.isEmpty) {
      throw const ValidationException('Name is required');
    }
    if (!isValidPin(pin)) {
      throw const ValidationException('PIN must be 4 to 8 digits');
    }
  }

  Future<void> _checkPinFree(String pin, {String? exceptUserId}) async {
    for (final user in await all()) {
      if (user.id != exceptUserId && user.pin == pin) {
        throw ValidationException('That PIN is already used by ${user.name}');
      }
    }
  }
}
