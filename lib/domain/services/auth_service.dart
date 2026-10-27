import '../../data/models/models.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../exceptions.dart';

class AuthService {
  AuthService(this._users, this._settings, {this.sessionScope = ''});

  final UserRepository _users;
  final SettingsRepository _settings;

  /// Extra key segment so terminals sharing one database keep separate staff
  /// sessions. Empty for a terminal on its own database.
  final String sessionScope;

  String get _sessionKey => sessionScope.isEmpty
      ? 'auth.lastUserId'
      : 'auth.lastUserId.$sessionScope';

  User? _session;

  User? get currentUser => _session;
  bool get isLoggedIn => _session != null;
  bool get isAdmin => _session?.isAdmin ?? false;

  /// Reopens the last signed-in user so the app skips the PIN screen on the
  /// next launch. A deleted or deactivated user falls back to the login screen.
  Future<void> restore() async {
    final id = await _settings.get(_sessionKey);
    if (id == null || id.isEmpty) return;
    final user = await _users.findById(id);
    if (user != null && user.active) _session = user;
  }

  Future<User> login(String pin) async {
    var user = await _users.loginByPin(pin.trim());
    try {
      // Recorded on the account so Admin Settings can show who has been using
      // the software. A failed write must not stop the sign-in itself.
      final at = DateTime.now().millisecondsSinceEpoch;
      await _users.markLogin(user.id, at);
      user = user.copyWith(lastLoginAt: at);
    } catch (_) {
      // Keep the login working even if the timestamp could not be saved.
    }
    _session = user;
    await _settings.set(_sessionKey, user.id);
    return user;
  }

  Future<void> logout() async {
    _session = null;
    await _settings.set(_sessionKey, '');
  }

  User requireUser() {
    final u = _session;
    if (u == null) throw const PermissionDeniedException('Not logged in');
    return u;
  }

  User requireAdmin() {
    final u = requireUser();
    if (!u.isAdmin) throw const PermissionDeniedException('Admin only');
    return u;
  }

  Future<List<User>> allUsers() => _users.all();

  /// True when [pin] matches an active admin user. Lets a screen require an
  /// admin's approval without signing the current user out and back in.
  Future<bool> verifyAdminPin(String pin) async {
    final clean = pin.trim();
    if (clean.isEmpty) return false;
    final users = await _users.all();
    return users.any((u) => u.isAdmin && u.active && u.pin == clean);
  }

  /// True when [pin] matches any active user (admin or staff). Used for
  /// actions that allow staff approval.
  Future<bool> verifyAnyPin(String pin) async {
    final clean = pin.trim();
    if (clean.isEmpty) return false;
    final users = await _users.all();
    return users.any((u) => u.active && u.pin == clean);
  }
}
