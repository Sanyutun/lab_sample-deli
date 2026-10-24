import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../data/models/models.dart';
import '../../data/repositories/cash_repository.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/companion_account_repository.dart';
import '../../data/repositories/delivery_man_repository.dart';
import '../../data/repositories/location_repository.dart';
import '../../data/repositories/milestone_repository.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../delivery_board.dart';
import '../exceptions.dart';
import '../ids.dart';
import '../period.dart';
import 'audit_service.dart';
import 'trip_service.dart';

/// The authenticated companion caller: which account and delivery man a bearer
/// token maps to. Data is always read for [man] only, so one delivery man can
/// never reach another's records.
class CompanionIdentity {
  const CompanionIdentity({required this.account, required this.man});

  final DeliveryManAccount account;
  final DeliveryMan man;
}

/// Authoritative companion-app logic. This is the *only* place companion data
/// is derived, and it reuses the office app's own repositories so commissions,
/// payments and rewards are the same numbers staff see.
///
/// Financial data is read-only here by construction: the service exposes no
/// method that writes a commission, payment, reward or rule.
class CompanionService {
  CompanionService({
    required this.accounts,
    required this.locations,
    required this.trips,
    required this.commissions,
    required this.milestones,
    required this.deliveryMen,
    required this.cash,
    required this.receipts,
    required this.audit,
    required this.settings,
  });

  final CompanionAccountRepository accounts;
  final LocationRepository locations;
  final TripService trips;
  final CommissionRepository commissions;
  final MilestoneRepository milestones;
  final DeliveryManRepository deliveryMen;
  final CashRepository cash;
  final ReceiptRepository receipts;
  final AuditService audit;
  final SettingsRepository settings;

  /// Sessions last 30 days; staff can revoke earlier.
  static const int sessionTtlMs = 30 * 24 * 60 * 60 * 1000;

  // Keys for the office-wide GPS policy in the settings table.
  static const String _gpsIntervalKey = 'companion.gpsIntervalMinutes';
  static const String _gpsRetentionKey = 'companion.gpsRetentionMinutes';

  // ---------- GPS policy (office/admin only) ----------

  /// The office's GPS policy for every companion phone. Falls back to the
  /// standard values when unset or no longer a valid preset.
  Future<GpsPolicyDto> gpsPolicy() async {
    final interval = int.tryParse(await settings.get(_gpsIntervalKey) ?? '');
    final retention = int.tryParse(await settings.get(_gpsRetentionKey) ?? '');
    return GpsPolicyDto(
      intervalMinutes: GpsPolicyDto.intervalOptions.contains(interval)
          ? interval!
          : GpsPolicyDto.standard.intervalMinutes,
      retentionMinutes: GpsPolicyDto.retentionOptions.contains(retention)
          ? retention!
          : GpsPolicyDto.standard.retentionMinutes,
    );
  }

  /// Saves the GPS policy phones pick up the next time they sign in. Rejects
  /// anything outside the shared presets so a phone can never receive a value
  /// its UI cannot show.
  Future<void> saveGpsPolicy(GpsPolicyDto policy) async {
    if (!GpsPolicyDto.intervalOptions.contains(policy.intervalMinutes)) {
      throw const ValidationException('Unsupported tracking interval');
    }
    if (!GpsPolicyDto.retentionOptions.contains(policy.retentionMinutes)) {
      throw const ValidationException('Unsupported phone retention');
    }
    await settings.set(_gpsIntervalKey, '${policy.intervalMinutes}');
    await settings.set(_gpsRetentionKey, '${policy.retentionMinutes}');
    await audit.record(
      'COMPANION_GPS_POLICY_CHANGED',
      newValue:
          'interval=${policy.intervalMinutes}m retention=${policy.retentionMinutes}m',
    );
  }

  // ---------- account administration (office/admin only) ----------

  Future<List<DeliveryManAccount>> allAccounts() => accounts.all();

  Future<DeliveryManAccount?> accountForDeliveryMan(String deliveryManId) =>
      accounts.findByDeliveryManId(deliveryManId);

  Future<DeliveryManAccount> registerAccount({
    required String deliveryManId,
    required String loginId,
    required String pin,
  }) async {
    final man = await deliveryMen.findById(deliveryManId);
    if (man == null) throw const NotFoundException('Delivery man not found');
    final cleanLogin = loginId.trim();
    if (cleanLogin.length < 3) {
      throw const ValidationException('Login ID must be at least 3 characters');
    }
    _requirePin(pin);
    if (await accounts.findByLoginId(cleanLogin) != null) {
      throw const ValidationException('That login ID is already in use');
    }
    if (await accounts.findByDeliveryManId(deliveryManId) != null) {
      throw const ValidationException(
        'This delivery man already has an account',
      );
    }
    final salt = newSalt();
    final account = await accounts.create(
      deliveryManId: deliveryManId,
      loginId: cleanLogin,
      pinHash: hashPin(pin, salt),
      salt: salt,
    );
    await audit.record(
      'COMPANION_ACCOUNT_CREATED',
      refId: account.id,
      newValue: '${man.name} login=$cleanLogin',
    );
    return account;
  }

  Future<void> setActive(String accountId, bool active) async {
    final account = await accounts.findById(accountId);
    if (account == null) throw const NotFoundException('Account not found');
    await accounts.update(account.copyWith(active: active));
    if (!active) await _revokeAllSessions(accountId);
    await audit.record(
      'COMPANION_ACCOUNT_STATUS',
      refId: accountId,
      newValue: active ? 'active' : 'deactivated',
    );
  }

  Future<void> resetPin(String accountId, String pin) async {
    _requirePin(pin);
    final account = await accounts.findById(accountId);
    if (account == null) throw const NotFoundException('Account not found');
    final salt = newSalt();
    await accounts.update(
      account.copyWith(pinHash: hashPin(pin, salt), salt: salt),
    );
    // A PIN reset ends every existing session for that account.
    await _revokeAllSessions(accountId);
    await audit.record('COMPANION_PIN_RESET', refId: accountId);
  }

  /// Issues a fresh QR token and returns the raw payload to display once. Only
  /// the hash is stored, so the code can be revoked without keeping a secret on
  /// disk. Rotating invalidates any previously issued code.
  Future<QrIdentityDto> rotateQr(String accountId) async {
    final account = await accounts.findById(accountId);
    if (account == null) throw const NotFoundException('Account not found');
    final token = randomToken();
    final issuedAt = nowMs();
    await accounts.update(
      account.copyWith(qrTokenHash: sha256Hex(token), qrIssuedAt: issuedAt),
    );
    await audit.record('COMPANION_QR_ROTATED', refId: accountId);
    return QrIdentityDto(payload: qrPayloadFor(token), issuedAt: issuedAt);
  }

  /// Revokes the current QR code without issuing a new one.
  Future<void> revokeQr(String accountId) async {
    final account = await accounts.findById(accountId);
    if (account == null) throw const NotFoundException('Account not found');
    await accounts.update(account.copyWith(clearQr: true));
    await audit.record('COMPANION_QR_REVOKED', refId: accountId);
  }

  // ---------- authentication ----------

  Future<AuthSessionDto> login({
    required String loginId,
    required String pin,
  }) async {
    final cleanLogin = loginId.trim();
    final account = await accounts.findByLoginId(cleanLogin);
    if (account == null || account.pinHash != hashPin(pin, account.salt)) {
      throw const ValidationException('Invalid ID or PIN');
    }
    if (!account.active) {
      throw const PermissionDeniedException('Account is deactivated');
    }
    final man = await deliveryMen.findById(account.deliveryManId);
    if (man == null) throw const NotFoundException('Delivery man not found');
    if (!man.active) {
      throw const PermissionDeniedException('Delivery man is inactive');
    }

    final token = randomToken();
    final expiresAt = nowMs() + sessionTtlMs;
    await accounts.createSession(
      accountId: account.id,
      tokenHash: sha256Hex(token),
      expiresAt: expiresAt,
    );
    await accounts.update(account.copyWith(lastLoginAt: nowMs()));
    await audit.record(
      'COMPANION_LOGIN',
      refId: account.id,
      newValue: man.name,
    );
    return AuthSessionDto(
      token: token,
      expiresAt: expiresAt,
      profile: _profile(man),
    );
  }

  /// Validates a bearer token. Throws [PermissionDeniedException] when the
  /// session is missing, revoked, expired, or belongs to an inactive account.
  Future<CompanionIdentity> authenticate(String? bearerToken) async {
    if (bearerToken == null || bearerToken.isEmpty) {
      throw const PermissionDeniedException('Missing session token');
    }
    final session = await accounts.findSessionByHash(sha256Hex(bearerToken));
    if (session == null || !session.isLiveAt(nowMs())) {
      throw const PermissionDeniedException('Invalid or expired session');
    }
    final account = await accounts.findById(session.accountId);
    if (account == null || !account.active) {
      throw const PermissionDeniedException('Account is deactivated');
    }
    final man = await deliveryMen.findById(account.deliveryManId);
    if (man == null || !man.active) {
      throw const PermissionDeniedException('Delivery man is inactive');
    }
    return CompanionIdentity(account: account, man: man);
  }

  Future<void> logout(String? bearerToken) async {
    if (bearerToken == null || bearerToken.isEmpty) return;
    final session = await accounts.findSessionByHash(sha256Hex(bearerToken));
    if (session == null) return;
    await accounts.updateSession(
      DeliverySession(
        id: session.id,
        accountId: session.accountId,
        tokenHash: session.tokenHash,
        createdAt: session.createdAt,
        expiresAt: session.expiresAt,
        revokedAt: nowMs(),
      ),
    );
  }

  // ---------- QR verification (office side) ----------

  /// Verifies a scanned QR token against the shared store. Returns the identity
  /// or null when the token is unknown, revoked or inactive — the office must
  /// then refuse to assign a receipt.
  Future<DeliveryManProfileDto?> verifyQr(String? token) async {
    if (token == null || token.isEmpty) return null;
    final account = await accounts.findByQrTokenHash(sha256Hex(token));
    if (account == null || !account.active) return null;
    final man = await deliveryMen.findById(account.deliveryManId);
    if (man == null || !man.active) return null;
    return _profile(man);
  }

  // ---------- read-only data ----------

  Future<DeliveryManProfileDto> profile(CompanionIdentity identity) async =>
      _profile(identity.man);

  /// Totals for the dashboard, computed from the same transactions staff see.
  Future<SummaryDto> summary(String deliveryManId) async {
    final records = await commissions.all(deliveryManId: deliveryManId);
    final active = records.where((r) => r.isActive).toList();
    final rewards = (await milestones.rewards(deliveryManId: deliveryManId))
        .where((r) => r.status == RecordStatus.active)
        .toList();

    final commissionEarned = active.fold<int>(0, (s, r) => s + r.commission);
    final commissionPaid = active
        .where((r) => r.isPaid)
        .fold<int>(0, (s, r) => s + r.commission);
    final rewardsEarned = rewards.fold<int>(0, (s, r) => s + r.rewardAmount);
    final rewardsPaid = rewards
        .where((r) => r.isPaid)
        .fold<int>(0, (s, r) => s + r.rewardAmount);

    return SummaryDto(
      successfulDeliveries: active.length,
      commissionEarned: commissionEarned,
      commissionPaid: commissionPaid,
      unpaidCommission: commissionEarned - commissionPaid,
      rewardsEarned: rewardsEarned,
      rewardsPaid: rewardsPaid,
      unpaidRewards: rewardsEarned - rewardsPaid,
    );
  }

  Future<List<CommissionDto>> listCommissions(
    String deliveryManId, {
    String? from,
    String? to,
    String? paymentStatus,
  }) async {
    final records = await commissions.all(deliveryManId: deliveryManId);
    final recon = await receipts.latestStatusByBarcode();
    final ledger = await cash.ledger();

    final list = records.where((r) => r.isActive).where((r) {
      final iso = isoDateOf(r.dateTime);
      if (from != null && from.isNotEmpty && iso.compareTo(from) < 0) {
        return false;
      }
      if (to != null && to.isNotEmpty && iso.compareTo(to) > 0) return false;
      if (paymentStatus == 'paid' && !r.isPaid) return false;
      if (paymentStatus == 'unpaid' && r.isPaid) return false;
      return true;
    }).toList();

    return [for (final r in list) _commissionDto(r, recon[r.barcode], ledger)];
  }

  Future<CommissionDto?> commissionDetail(
    String deliveryManId,
    String recordId,
  ) async {
    final record = await commissions.findById(recordId);
    // Isolation: a record that is not this delivery man's does not exist here.
    if (record == null || record.deliveryManId != deliveryManId) return null;
    final recon = await receipts.latestStatusByBarcode();
    final ledger = await cash.ledger();
    return _commissionDto(record, recon[record.barcode], ledger);
  }

  Future<List<RewardDto>> listRewards(String deliveryManId) async {
    final rewards = await milestones.rewards(deliveryManId: deliveryManId);
    return [
      for (final r in rewards.where((r) => r.status == RecordStatus.active))
        RewardDto(
          id: r.id,
          everyN: r.everyN,
          milestoneCount: r.milestoneCount,
          rewardAmount: r.rewardAmount,
          paymentStatus: r.paymentStatus.name,
          createdAt: r.createdAt,
          paidAt: r.paidAt,
        ),
    ];
  }

  /// The delivery man's own board, built from the same records, rewards and
  /// reconciliation results the office screen uses, so the two can never show
  /// different numbers. Read-only: the board creates no transaction.
  Future<DeliveryBoardDto> deliveryBoard(String deliveryManId) async {
    final records = await commissions.all(deliveryManId: deliveryManId);
    final rewards = await milestones.rewards(deliveryManId: deliveryManId);
    final recon = await receipts.latestStatusByBarcode();
    final board = DeliveryBoard.from(
      records: records,
      rewards: rewards,
      reconciliationByBarcode: recon,
    );
    final s = board.summary;
    return DeliveryBoardDto(
      summary: BoardSummaryDto(
        successfulDeliveries: s.successfulDeliveries,
        totalSlots: s.totalSlots,
        commissionEarned: s.commissionEarned,
        commissionPaid: s.commissionPaid,
        unpaidCommission: s.unpaidCommission,
        rewardsEarned: s.rewardsEarned,
        rewardsPaid: s.rewardsPaid,
        unpaidBalance: s.unpaidBalance,
      ),
      // Only groups that hold a delivery are sent: the full board is 200 mostly
      // empty groups, far more than a phone needs. Positions and numbering are
      // unchanged, so a slot still means the same number on both sides.
      groups: [
        for (final g in board.groups)
          if (g.slots.any((sl) => !sl.isEmpty))
            BoardGroupDto(
              groupNumber: g.groupNumber,
              startNumber: g.startNumber,
              endNumber: g.endNumber,
              successfulCount: g.successfulCount,
              commissionTotal: g.commissionTotal,
              milestoneAmounts: g.milestoneAmounts,
              slots: [
                for (final sl in g.slots)
                  BoardSlotDto(
                    number: sl.number,
                    state: sl.state.name,
                    commission: sl.commission,
                    paid: sl.record?.paymentStatus == PaymentStatus.paid,
                    milestoneAmount: sl.milestoneAmount,
                    barcode: sl.record?.barcode,
                    recordedAt: sl.record?.dateTime,
                    reconciliationStatus: sl.reconciliationStatus?.name,
                  ),
              ],
            ),
      ],
      slotsPerGroup: board.slotsPerGroup,
      totalSlots: board.totalSlots,
    );
  }

  // ---------- GPS ----------

  Future<GeoPointDto> recordLocation(
    String deliveryManId, {
    required double latitude,
    required double longitude,
    double? accuracyM,
    int? capturedAt,
    String? barcode,
    String? clientId,
  }) async {
    if (latitude < -90 || latitude > 90) {
      throw const ValidationException('Latitude out of range');
    }
    if (longitude < -180 || longitude > 180) {
      throw const ValidationException('Longitude out of range');
    }
    if (accuracyM != null && accuracyM < 0) {
      throw const ValidationException('Accuracy cannot be negative');
    }
    final client = (clientId == null || clientId.trim().isEmpty)
        ? null
        : clientId.trim();

    // A phone that queued fixes retries one it never saw the reply to. If that
    // fix is already stored, hand it back instead of inserting a duplicate.
    // shortcut: checked before insert rather than by catching a unique-index
    // clash; a phone has a single sync writer, so there is no race to lose.
    if (client != null) {
      final existing = await locations.findByClientId(deliveryManId, client);
      if (existing != null) return _toDto(existing);
    }

    final now = nowMs();
    // Guard a wrong device clock: never accept a timestamp in the future.
    final when = (capturedAt == null || capturedAt <= 0 || capturedAt > now)
        ? now
        : capturedAt;

    final location = DeliveryLocation(
      id: newId('geo'),
      deliveryManId: deliveryManId,
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      capturedAt: when,
      receivedAt: now,
      barcode: (barcode == null || barcode.trim().isEmpty)
          ? null
          : barcode.trim(),
      clientId: client,
    );
    await locations.insert(location);
    // A fix that only just arrived may belong to a delivery already recorded
    // while this phone was offline; attach it before the fix ages out.
    await trips.attachLateFix(location);
    // Raw fixes are only kept for the retention window; routes already saved
    // against a delivery are copies and survive this.
    await trips.purgeOldRawFixes(now: now);
    return _toDto(location);
  }

  Future<List<GeoPointDto>> listLocations(String deliveryManId) async {
    final list = await locations.forDeliveryMan(deliveryManId);
    return [for (final l in list) _toDto(l)];
  }

  /// The preserved route of one of this man's own receipts. Returns null when
  /// no route was kept, or when the receipt is not this man's (so one man can
  /// never read another's route).
  Future<TripHistoryDto?> tripHistory(
    String deliveryManId,
    String barcode,
  ) async {
    final CommissionRecord record;
    try {
      record = await commissions.findByBarcode(barcode.trim());
    } on NotFoundException {
      return null;
    }
    if (record.deliveryManId != deliveryManId) return null;
    final points = await trips.routeForBarcode(barcode);
    return TripHistoryDto(
      barcode: record.barcode,
      commissionId: record.id,
      verifiedAt: record.dateTime,
      points: [
        for (final p in points)
          TripPointDto(
            id: p.id,
            latitude: p.latitude,
            longitude: p.longitude,
            capturedAt: p.capturedAt,
            accuracyM: p.accuracyM,
          ),
      ],
    );
  }

  GeoPointDto _toDto(DeliveryLocation l) => GeoPointDto(
    id: l.id,
    latitude: l.latitude,
    longitude: l.longitude,
    accuracyM: l.accuracyM,
    capturedAt: l.capturedAt,
    barcode: l.barcode,
    clientId: l.clientId,
  );

  // ---------- helpers ----------

  void _requirePin(String pin) {
    if (pin.trim().length < 4) {
      throw const ValidationException('PIN must be at least 4 digits');
    }
  }

  Future<void> _revokeAllSessions(String accountId) async {
    for (final s in await accounts.sessionsFor(accountId)) {
      if (s.revokedAt != null) continue;
      await accounts.updateSession(
        DeliverySession(
          id: s.id,
          accountId: s.accountId,
          tokenHash: s.tokenHash,
          createdAt: s.createdAt,
          expiresAt: s.expiresAt,
          revokedAt: nowMs(),
        ),
      );
    }
  }

  DeliveryManProfileDto _profile(DeliveryMan man) =>
      DeliveryManProfileDto(id: man.id, name: man.name, phone: man.phone);

  CommissionDto _commissionDto(
    CommissionRecord r,
    ReconciliationStatus? recon,
    List<CashTransaction> ledger,
  ) {
    final payments = ledger
        .where((t) => t.refId == r.id)
        .map(
          (t) => PaymentEntryDto(
            type: t.type.name,
            amount: t.amount,
            date: t.date,
            note: t.note,
          ),
        )
        .toList();
    return CommissionDto(
      id: r.id,
      barcode: r.barcode,
      commission: r.commission,
      dateTime: r.dateTime,
      paymentStatus: r.paymentStatus.name,
      reconciliationStatus: recon?.name ?? 'unknown',
      paidAt: r.paidAt,
      payments: payments,
    );
  }
}
