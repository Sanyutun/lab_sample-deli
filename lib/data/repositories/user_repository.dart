import '../../domain/exceptions.dart';
import '../../domain/ids.dart';
import '../models/models.dart';
import '../storage/app_storage.dart';

class UserRepository {
  UserRepository(this._storage);
  final AppStorage _storage;

  static const String _table = 'users';

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
    final user = User(
      id: newId('usr'),
      name: name,
      pin: pin,
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
    final users = await all();
    for (final u in users) {
      if (u.pin == pin) {
        if (!u.active) {
          throw const PermissionDeniedException('User is deactivated');
        }
        return u;
      }
    }
    throw const ValidationException('Wrong PIN');
  }

  Future<void> update(User user) async {
    await _storage.update(_table, {'id': user.id}, user.toMap());
  }
}
