import '../models/models.dart';
import '../storage/app_storage.dart';
import '../../domain/ids.dart';

class AuditRepository {
  AuditRepository(this._storage);
  final AppStorage _storage;

  static const String _table = 'audit_logs';

  Future<void> log({
    required String userId,
    required String userName,
    required String action,
    String? refId,
    String? oldValue,
    String? newValue,
  }) async {
    final entry = AuditLog(
      id: newId('aud'),
      userId: userId,
      userName: userName,
      action: action,
      refId: refId,
      oldValue: oldValue,
      newValue: newValue,
      createdAt: nowMs(),
    );
    await _storage.insert(_table, entry.toMap());
  }

  Future<List<AuditLog>> all() async {
    final rows = await _storage.find(_table, orderBy: '-created_at');
    return rows.map(AuditLog.fromMap).toList();
  }

  /// Entries recorded against one transaction, reward or other record.
  Future<List<AuditLog>> forRef(String refId) async {
    final rows = await _storage.find(
      _table,
      where: {'ref_id': refId},
      orderBy: '-created_at',
    );
    return rows.map(AuditLog.fromMap).toList();
  }
}
