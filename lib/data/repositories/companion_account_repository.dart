import '../../domain/ids.dart';
import '../models/models.dart';
import '../storage/app_storage.dart';

/// Companion accounts and their bearer sessions.
class CompanionAccountRepository {
  CompanionAccountRepository(this._storage);
  final AppStorage _storage;

  static const String accountsTable = 'delivery_man_accounts';
  static const String sessionsTable = 'delivery_sessions';

  // ---- accounts ----

  Future<DeliveryManAccount> create({
    required String deliveryManId,
    required String loginId,
    required String pinHash,
    required String salt,
    bool active = true,
  }) async {
    final account = DeliveryManAccount(
      id: newId('dma'),
      deliveryManId: deliveryManId,
      loginId: loginId,
      pinHash: pinHash,
      salt: salt,
      active: active,
      createdAt: nowMs(),
    );
    await _storage.insert(accountsTable, account.toMap());
    return account;
  }

  Future<void> update(DeliveryManAccount account) async {
    await _storage.update(accountsTable, {'id': account.id}, account.toMap());
  }

  Future<DeliveryManAccount?> findById(String id) async {
    final m = await _storage.findOne(accountsTable, {'id': id});
    return m == null ? null : DeliveryManAccount.fromMap(m);
  }

  Future<DeliveryManAccount?> findByDeliveryManId(String deliveryManId) async {
    final m = await _storage.findOne(accountsTable, {
      'delivery_man_id': deliveryManId,
    });
    return m == null ? null : DeliveryManAccount.fromMap(m);
  }

  Future<DeliveryManAccount?> findByLoginId(String loginId) async {
    final m = await _storage.findOne(accountsTable, {'login_id': loginId});
    return m == null ? null : DeliveryManAccount.fromMap(m);
  }

  Future<DeliveryManAccount?> findByQrTokenHash(String tokenHash) async {
    final m = await _storage.findOne(accountsTable, {
      'qr_token_hash': tokenHash,
    });
    return m == null ? null : DeliveryManAccount.fromMap(m);
  }

  Future<List<DeliveryManAccount>> all() async {
    final rows = await _storage.find(accountsTable, orderBy: 'login_id');
    return rows.map(DeliveryManAccount.fromMap).toList();
  }

  // ---- sessions ----

  Future<DeliverySession> createSession({
    required String accountId,
    required String tokenHash,
    required int expiresAt,
  }) async {
    final session = DeliverySession(
      id: newId('sess'),
      accountId: accountId,
      tokenHash: tokenHash,
      createdAt: nowMs(),
      expiresAt: expiresAt,
    );
    await _storage.insert(sessionsTable, session.toMap());
    return session;
  }

  Future<DeliverySession?> findSessionByHash(String tokenHash) async {
    final m = await _storage.findOne(sessionsTable, {'token_hash': tokenHash});
    return m == null ? null : DeliverySession.fromMap(m);
  }

  Future<void> updateSession(DeliverySession session) async {
    await _storage.update(sessionsTable, {'id': session.id}, session.toMap());
  }

  Future<List<DeliverySession>> sessionsFor(String accountId) async {
    final rows = await _storage.find(
      sessionsTable,
      where: {'account_id': accountId},
    );
    return rows.map(DeliverySession.fromMap).toList();
  }

  Future<void> purgeExpired(int now) async {
    final rows = await _storage.find(sessionsTable);
    for (final m in rows) {
      final session = DeliverySession.fromMap(m);
      if (now >= session.expiresAt || session.revokedAt != null) {
        await _storage.remove(sessionsTable, {'id': session.id});
      }
    }
  }
}
