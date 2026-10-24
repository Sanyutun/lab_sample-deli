import '../../data/models/models.dart';
import '../../data/repositories/cash_repository.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/milestone_repository.dart';
import '../exceptions.dart';
import '../ids.dart';
import 'audit_service.dart';

/// Cash control: advances in, commission/reward payments out.
/// The remaining balance is ALWAYS derived from the ledger.
class CashService {
  CashService({
    required this.cash,
    required this.commissions,
    required this.milestones,
    required this.audit,
  });

  final CashRepository cash;
  final CommissionRepository commissions;
  final MilestoneRepository milestones;
  final AuditService audit;

  Future<CashAdvance> addAdvance({
    required int amount,
    String note = '',
    String? date,
    required String createdBy,
  }) async {
    if (amount <= 0) {
      throw const ValidationException('Advance must be positive');
    }
    final advance = await cash.insertAdvance(
      date: date ?? todayIso(),
      amount: amount,
      note: note,
      createdBy: createdBy,
    );
    await cash.insertTxn(
      type: CashTxnType.advance,
      amount: amount,
      refType: 'cash_advance',
      refId: advance.id,
      date: advance.date,
      note: note.isEmpty ? 'Owner cash advance' : note,
      createdBy: createdBy,
    );
    await audit.record(
      'CASH_ADVANCE_ADDED',
      refId: advance.id,
      newValue: '$amount MMK on ${advance.date}',
    );
    return advance;
  }

  /// Actual cash payment of an earned commission to the delivery man.
  Future<void> payCommission({
    required String recordId,
    required String staffUserId,
  }) async {
    final record = await commissions.findById(recordId);
    if (record == null) throw const NotFoundException('Transaction not found');
    if (!record.isActive) {
      throw const ValidationException('Cannot pay a reversed record');
    }
    if (record.isPaid) {
      throw const ValidationException('Commission already paid');
    }
    if (await cash.netFor(recordId) != 0) {
      throw const ValidationException('Cash payment already recorded');
    }
    await commissions.updateRecord(
      record.copyWith(
        paymentStatus: PaymentStatus.paid,
        paidAt: nowMs(),
        paidBy: staffUserId,
      ),
    );
    await cash.insertTxn(
      type: CashTxnType.commissionPayment,
      amount: -record.commission,
      refType: 'commission_record',
      refId: record.id,
      note: 'Commission payment ${record.barcode}',
      createdBy: staffUserId,
    );
    await audit.record(
      'COMMISSION_PAID',
      refId: recordId,
      newValue: '-${record.commission} MMK',
    );
  }

  /// Undoes a commission payment (paid -> unpaid) and returns the money to the
  /// cash box with a linked compensating entry, so balances and the paid
  /// reports stay correct. The original payment entry is kept for audit.
  Future<void> unpayCommission({
    required String recordId,
    required String byUserId,
  }) async {
    final record = await commissions.findById(recordId);
    if (record == null) throw const NotFoundException('Transaction not found');
    if (!record.isActive) {
      throw const ValidationException(
        'Cannot change payment of a reversed record',
      );
    }
    if (!record.isPaid) {
      throw const ValidationException('Commission is not paid');
    }
    await commissions.updateRecord(
      record.copyWith(paymentStatus: PaymentStatus.unpaid, clearPaid: true),
    );
    if (await cash.netFor(recordId) != 0) {
      await returnCommissionToCash(
        record: record,
        note: 'Un-pay correction ${record.barcode}',
        byUserId: byUserId,
      );
    }
    await audit.record(
      'COMMISSION_UNPAID',
      refId: recordId,
      newValue: '${record.commission} MMK',
    );
  }

  /// Posts a compensating ledger entry that returns a previously paid
  /// commission to the cash box (used when un-paying or reversing a record).
  Future<void> returnCommissionToCash({
    required CommissionRecord record,
    required String note,
    required String byUserId,
  }) async {
    await cash.insertTxn(
      type: CashTxnType.commissionPayment,
      amount: record.commission,
      refType: 'commission_record',
      refId: record.id,
      note: note,
      createdBy: byUserId,
    );
  }

  Future<void> payMilestoneReward({
    required String rewardId,
    required String staffUserId,
  }) async {
    final reward = await milestones.findReward(rewardId);
    if (reward == null) throw const NotFoundException('Reward not found');
    if (reward.paymentStatus == PaymentStatus.paid) {
      throw const ValidationException('Reward already paid');
    }
    if (await cash.hasTxnFor(rewardId)) {
      throw const ValidationException('Cash payment already recorded');
    }
    await milestones.updateReward(
      reward.copyWith(
        paymentStatus: PaymentStatus.paid,
        paidAt: nowMs(),
        paidBy: staffUserId,
      ),
    );
    await cash.insertTxn(
      type: CashTxnType.rewardPayment,
      amount: -reward.rewardAmount,
      refType: 'milestone_reward',
      refId: reward.id,
      note: 'Reward ${reward.everyN} deliveries',
      createdBy: staffUserId,
    );
    await audit.record(
      'REWARD_PAID',
      refId: rewardId,
      newValue: '-${reward.rewardAmount} MMK',
    );
  }

  /// Undoes a reward payment (paid -> unpaid) and returns the money to the
  /// cash box with a linked compensating entry, so balances and the paid
  /// reports stay correct. The original payment entry is kept for audit.
  Future<void> unpayMilestoneReward({
    required String rewardId,
    required String byUserId,
  }) async {
    final reward = await milestones.findReward(rewardId);
    if (reward == null) throw const NotFoundException('Reward not found');
    if (reward.paymentStatus != PaymentStatus.paid) {
      throw const ValidationException('Reward is not paid');
    }
    await milestones.updateReward(
      reward.copyWith(paymentStatus: PaymentStatus.unpaid, clearPaid: true),
    );
    if (await cash.netFor(rewardId) != 0) {
      await cash.insertTxn(
        type: CashTxnType.rewardPayment,
        amount: reward.rewardAmount,
        refType: 'milestone_reward',
        refId: reward.id,
        note: 'Un-pay correction ${reward.everyN} deliveries',
        createdBy: byUserId,
      );
    }
    await audit.record(
      'REWARD_UNPAID',
      refId: rewardId,
      newValue: '${reward.rewardAmount} MMK',
    );
  }

  Future<void> otherPayment({
    required int amount,
    required String note,
    required String createdBy,
  }) async {
    if (amount <= 0) throw const ValidationException('Amount must be positive');
    await cash.insertTxn(
      type: CashTxnType.otherOut,
      amount: -amount,
      note: note,
      createdBy: createdBy,
    );
    await audit.record('OTHER_PAYMENT', newValue: '-$amount MMK | $note');
  }

  Future<void> otherIncome({
    required int amount,
    required String note,
    required String createdBy,
  }) async {
    if (amount <= 0) throw const ValidationException('Amount must be positive');
    await cash.insertTxn(
      type: CashTxnType.otherIn,
      amount: amount,
      note: note,
      createdBy: createdBy,
    );
    await audit.record('OTHER_INCOME', newValue: '+$amount MMK | $note');
  }

  Future<List<CashTransaction>> ledger() => cash.ledger();

  /// Net cash still linked to a reference (0 once a payment is fully settled).
  Future<int> netFor(String refId) => cash.netFor(refId);

  Future<int> balance({String? throughDate}) =>
      cash.balance(throughDate: throughDate);

  Future<List<CashAdvance>> advances() => cash.advances();

  // ---- separated earned vs paid ----

  Future<int> commissionEarned({String? onDate}) async {
    final all = await commissions.all(status: RecordStatus.active);
    int total = 0;
    for (final r in all) {
      if (onDate == null || _dateOf(r.dateTime) == onDate) {
        total += r.commission;
      }
    }
    return total;
  }

  Future<int> commissionPaid({String? onDate}) async =>
      _sumOf(CashTxnType.commissionPayment, onDate);

  /// Repairs the ledger for records marked paid by builds that flipped the paid
  /// flag without writing the matching cash entry (which made "commission paid"
  /// report 0). Posts the missing payment for every paid, active record that has
  /// no ledger effect yet. Idempotent — safe to run on every startup.
  Future<int> repairMissingCommissionPayments() async {
    var repaired = 0;
    for (final r in await commissions.all()) {
      if (!r.isActive || !r.isPaid) continue;
      if (await cash.netFor(r.id) != 0) continue;
      await cash.insertTxn(
        type: CashTxnType.commissionPayment,
        amount: -r.commission,
        refType: 'commission_record',
        refId: r.id,
        date: _dateOf(r.paidAt ?? r.dateTime),
        note: 'Commission payment ${r.barcode}',
        createdBy: r.paidBy ?? 'system',
      );
      repaired++;
    }
    if (repaired > 0) {
      await audit.record(
        'COMMISSION_LEDGER_REPAIRED',
        newValue: '$repaired record(s)',
      );
    }
    return repaired;
  }

  Future<int> rewardsPaid({String? onDate}) async =>
      _sumOf(CashTxnType.rewardPayment, onDate);

  Future<int> otherPaymentsOut({String? onDate}) async =>
      _sumOf(CashTxnType.otherOut, onDate);

  Future<int> advancesReceived({String? onDate}) async {
    final list = await cash.advances();
    int total = 0;
    for (final a in list) {
      if (onDate == null || a.date == onDate) total += a.amount;
    }
    return total;
  }

  Future<int> _sumOf(CashTxnType type, String? onDate) async {
    final rows = await cash.ledger();
    var total = 0;
    for (final t in rows) {
      if (t.type != type) continue;
      if (onDate != null && t.date != onDate) continue;
      total += t.amount;
    }
    return total.abs();
  }

  String _dateOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
