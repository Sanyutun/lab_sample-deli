import '../../data/models/models.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/delivery_man_repository.dart';
import '../../data/repositories/milestone_repository.dart';
import '../exceptions.dart';
import '../ids.dart';
import 'audit_service.dart';
import 'cash_service.dart';
import 'trip_service.dart';

/// Result of a successful "record commission" action.
class RecordCommissionResult {
  const RecordCommissionResult({required this.record, required this.rewards});
  final CommissionRecord record;
  final List<MilestoneReward> rewards;
}

class DeliveryService {
  DeliveryService({
    required this.commissions,
    required this.deliveryMen,
    required this.milestones,
    required this.audit,
    required this.cash,
    required this.trips,
  });

  final CommissionRepository commissions;
  final DeliveryManRepository deliveryMen;
  final MilestoneRepository milestones;
  final AuditService audit;
  final CashService cash;
  final TripService trips;

  /// Core staff workflow: barcode + delivery man + commission amount.
  Future<RecordCommissionResult> recordCommission({
    required String barcode,
    required String deliveryManId,
    required int commission,
    required String staffUserId,
  }) async {
    final cleanBarcode = barcode.trim();
    if (cleanBarcode.isEmpty) {
      throw const ValidationException('Barcode is empty');
    }

    await deliveryMen.requireActive(deliveryManId);

    final selectable = await commissions.selectableAmounts();
    if (!selectable.contains(commission)) {
      throw ValidationException(
        'Commission must be one of: ${selectable.join(', ')} MMK',
      );
    }

    if (await commissions.hasActiveByBarcode(cleanBarcode)) {
      final existing = await commissions.findByBarcode(cleanBarcode);
      final manName = (await deliveryMen.findById(existing.deliveryManId))
          ?.name;
      throw DuplicateBarcodeException(
        existing.copyWith(deliveryManName: manName),
      );
    }

    final now = nowMs();
    final record = CommissionRecord(
      id: newId('txn'),
      barcode: cleanBarcode,
      deliveryManId: deliveryManId,
      commission: commission,
      dateTime: now,
      staffUserId: staffUserId,
      status: RecordStatus.active,
      paymentStatus: PaymentStatus.unpaid,
      createdAt: now,
    );

    await commissions.insert(record);
    await audit.record(
      'COMMISSION_RECORDED',
      refId: record.id,
      newValue: '$cleanBarcode | $deliveryManId | $commission MMK',
    );

    // Keep the man's last 20 minutes of fixes with this receipt. Never fatal:
    // the commission is already saved, and a missing route is reported as
    // missing rather than invented.
    try {
      await trips.preserveForDelivery(
        barcode: cleanBarcode,
        commissionId: record.id,
        deliveryManId: deliveryManId,
        verifiedAtMs: record.dateTime,
      );
    } on Exception {
      // Ignored on purpose — see above.
    }

    final rewards = await _checkMilestones(deliveryManId);
    return RecordCommissionResult(record: record, rewards: rewards);
  }

  Future<List<MilestoneReward>> _checkMilestones(String deliveryManId) async {
    final count = await commissions.activeCountFor(deliveryManId);
    if (count == 0) return const [];
    final rules = await milestones.rules(activeOnly: true);
    final created = <MilestoneReward>[];
    for (final rule in rules) {
      if (count % rule.everyN == 0) {
        if (await milestones.rewardExists(deliveryManId, rule.everyN, count)) {
          continue;
        }
        final reward = MilestoneReward(
          id: newId('rw'),
          deliveryManId: deliveryManId,
          everyN: rule.everyN,
          milestoneCount: count,
          rewardAmount: rule.rewardAmount,
          createdAt: nowMs(),
        );
        await milestones.insertReward(reward);
        await audit.record(
          'MILESTONE_REWARD_EARNED',
          refId: reward.id,
          newValue: '$count deliveries | ${rule.rewardAmount} MMK',
        );
        created.add(reward);
      }
    }
    return created;
  }

  Future<void> markPaid({
    required String recordId,
    required String staffUserId,
  }) => cash.payCommission(recordId: recordId, staffUserId: staffUserId);

  /// Toggles the payment status (paid <-> unpaid) of an active commission
  /// record. This goes through [CashService] so the cash ledger always gets the
  /// matching entry (a payment out, or a compensating return when un-paid):
  /// otherwise "commission paid" reports and the cash balance silently drift.
  /// Reversed records cannot be changed.
  Future<PaymentStatus> togglePaymentStatus({
    required String recordId,
    required String staffUserId,
  }) async {
    final record = await commissions.findById(recordId);
    if (record == null) throw const NotFoundException('Transaction not found');
    if (!record.isActive) {
      throw const ValidationException(
        'Cannot change payment of a reversed record',
      );
    }
    if (record.isPaid) {
      await cash.unpayCommission(recordId: recordId, byUserId: staffUserId);
      return PaymentStatus.unpaid;
    }
    await cash.payCommission(recordId: recordId, staffUserId: staffUserId);
    return PaymentStatus.paid;
  }

  /// Corrects the delivery man attached to an active commission record.
  /// Use this when the wrong delivery man was selected by mistake, instead of
  /// voiding and re-entering the transaction. The change is audited and the
  /// original record is kept. Milestone rewards already earned are historical
  /// and are not recalculated.
  Future<void> changeDeliveryMan({
    required String recordId,
    required String newDeliveryManId,
  }) async {
    final record = await commissions.findById(recordId);
    if (record == null) throw const NotFoundException('Transaction not found');
    if (!record.isActive) {
      throw const ValidationException('Cannot correct a reversed record');
    }
    if (record.deliveryManId == newDeliveryManId) return;
    final man = await deliveryMen.requireActive(newDeliveryManId);
    final previous = await deliveryMen.findById(record.deliveryManId);
    await commissions.updateRecord(
      record.copyWith(deliveryManId: newDeliveryManId),
    );
    await audit.record(
      'COMMISSION_DELIVERY_MAN_CHANGED',
      refId: recordId,
      oldValue: previous?.name ?? record.deliveryManId,
      newValue: man.name,
    );
  }

  /// Financial records are never deleted. Reversal keeps the original row.
  /// If the record had already been paid, the cash payment is returned to the
  /// cash box so the ledger stays balanced.
  Future<void> reverse({
    required String recordId,
    required String reason,
    required String byUserId,
  }) async {
    final record = await commissions.findById(recordId);
    if (record == null) throw const NotFoundException('Transaction not found');
    if (!record.isActive) throw const ValidationException('Already reversed');
    final wasPaid = record.isPaid && await cash.netFor(recordId) != 0;
    await commissions.updateRecord(
      record.copyWith(
        status: RecordStatus.reversed,
        reversedAt: nowMs(),
        reversedBy: byUserId,
        reversalReason: reason,
        paymentStatus: wasPaid ? PaymentStatus.unpaid : null,
        clearPaid: wasPaid,
      ),
    );
    if (wasPaid) {
      await cash.returnCommissionToCash(
        record: record,
        note: 'Void reversal ${record.barcode}: $reason',
        byUserId: byUserId,
      );
    }
    await audit.record(
      'COMMISSION_REVERSED',
      refId: recordId,
      oldValue: '${record.commission} MMK active',
      newValue: reason,
    );
  }

  Future<List<CommissionRecord>> history({
    String? staffUserId,
    String? deliveryManId,
  }) async {
    final all = await commissions.all(
      deliveryManId: deliveryManId,
      staffUserId: staffUserId,
    );
    return all;
  }
}
