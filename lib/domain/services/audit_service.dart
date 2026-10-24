import '../../data/models/models.dart';
import '../../data/repositories/audit_repository.dart';
import 'auth_service.dart';

class AuditService {
  AuditService(this._audit, this._auth);

  final AuditRepository _audit;
  final AuthService _auth;

  Future<void> record(
    String action, {
    String? refId,
    Object? oldValue,
    Object? newValue,
  }) async {
    final user = _auth.currentUser;
    await _audit.log(
      userId: user?.id ?? 'system',
      userName: user?.name ?? 'system',
      action: action,
      refId: refId,
      oldValue: oldValue?.toString(),
      newValue: newValue?.toString(),
    );
  }

  Future<List<AuditLog>> logs() => _audit.all();

  Future<List<AuditLog>> logsFor(String refId) => _audit.forRef(refId);
}
