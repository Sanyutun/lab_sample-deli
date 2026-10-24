import '../../data/models/models.dart';
import '../../data/repositories/cash_repository.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/delivery_man_repository.dart';
import '../../data/repositories/milestone_repository.dart';
import '../exceptions.dart';
import '../ids.dart';
import '../period.dart';
import 'audit_service.dart';

/// Combined cash + performance figures for a single reporting period.
class FinanceReport {
  const FinanceReport({
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.cashReceived,
    required this.otherIncome,
    required this.commissionEarned,
    required this.commissionPaid,
    required this.rewardsPaid,
    required this.otherPayments,
    required this.closingBalance,
    required this.deliveries,
    required this.performance,
    required this.ledger,
    required this.advances,
  });

  final String from;
  final String to;

  /// Remaining cash carried forward from before [from].
  final int openingBalance;
  final int cashReceived;
  final int otherIncome;
  final int commissionEarned;
  final int commissionPaid;
  final int rewardsPaid;
  final int otherPayments;

  /// Remaining cash as of the end of [to].
  final int closingBalance;
  final int deliveries;
  final List<DeliveryManPerformance> performance;
  final List<CashTransaction> ledger;
  final List<CashAdvance> advances;
}

class DeliveryManPerformance {
  const DeliveryManPerformance({
    required this.deliveryManId,
    required this.name,
    required this.deliveries,
    required this.commission,
    required this.rewards,
  });

  final String deliveryManId;
  final String name;
  final int deliveries;
  final int commission;
  final int rewards;

  int get total => commission + rewards;
}

class _Acc {
  _Acc(this.id, this.name);
  final String id;
  final String name;
  int deliveries = 0;
  int commission = 0;
  int rewards = 0;
}

/// Produces period reports and manages monthly closings (with carry-forward).
class FinanceService {
  FinanceService({
    required this.cash,
    required this.commissions,
    required this.milestones,
    required this.deliveryMen,
    required this.audit,
  });

  final CashRepository cash;
  final CommissionRepository commissions;
  final MilestoneRepository milestones;
  final DeliveryManRepository deliveryMen;
  final AuditService audit;

  Future<FinanceReport> report({
    required String from,
    required String to,
  }) async {
    final carryForward = await _carryForward(monthOfIso(from));
    final opening =
        await cash.balance(throughDate: dayBefore(from)) + carryForward;
    final ledger = (await cash.ledger())
        .where((t) => withinRange(t.date, from, to))
        .toList();
    final advances = (await cash.advances())
        .where((a) => withinRange(a.date, from, to))
        .toList();
    final records = (await commissions.all())
        .where(
          (r) => r.isActive && withinRange(isoDateOf(r.dateTime), from, to),
        )
        .toList();
    final rewards = (await milestones.rewards())
        .where(
          (rw) =>
              rw.status == RecordStatus.active &&
              withinRange(isoDateOf(rw.createdAt), from, to),
        )
        .toList();

    int sumOf(CashTxnType type) {
      var total = 0;
      for (final t in ledger) {
        if (t.type == type) total += t.amount;
      }
      return total;
    }

    final names = <String, String>{};
    for (final m in await deliveryMen.all()) {
      names[m.id] = m.name;
    }
    final acc = <String, _Acc>{};
    _Acc entry(String id) =>
        acc.putIfAbsent(id, () => _Acc(id, names[id] ?? id));
    for (final r in records) {
      final a = entry(r.deliveryManId);
      a.deliveries++;
      a.commission += r.commission;
    }
    for (final rw in rewards) {
      entry(rw.deliveryManId).rewards += rw.rewardAmount;
    }
    final performance =
        acc.values
            .map(
              (a) => DeliveryManPerformance(
                deliveryManId: a.id,
                name: a.name,
                deliveries: a.deliveries,
                commission: a.commission,
                rewards: a.rewards,
              ),
            )
            .toList()
          ..sort((x, y) => y.total.compareTo(x.total));

    return FinanceReport(
      from: from,
      to: to,
      openingBalance: opening,
      cashReceived: advances.fold<int>(0, (s, a) => s + a.amount),
      otherIncome: sumOf(CashTxnType.otherIn),
      commissionEarned: records.fold<int>(0, (s, r) => s + r.commission),
      commissionPaid: -sumOf(CashTxnType.commissionPayment),
      rewardsPaid: -sumOf(CashTxnType.rewardPayment),
      otherPayments: -sumOf(CashTxnType.otherOut),
      closingBalance: await cash.balance(throughDate: to) + carryForward,
      deliveries: records.length,
      performance: performance,
      ledger: ledger,
      advances: advances,
    );
  }

  /// Cumulative cash variance from every month closed before [month]. When a
  /// closing is saved its `difference` (actual counted − expected) is carried
  /// forward, so a physical shortfall or overage in one month becomes the
  /// opening balance of the following months.
  Future<int> _carryForward(String month) async {
    var total = 0;
    for (final c in await cash.closings()) {
      if (c.month.compareTo(month) < 0) total += c.difference;
    }
    return total;
  }

  /// Closings must be recorded in calendar order: a month's carried-forward
  /// opening balance depends on the closings already before it, so backfilling
  /// an earlier month after a later one would leave stale figures.
  Future<void> _ensureInOrder(String month) async {
    final later = (await cash.closings()).where(
      (c) => c.month.compareTo(month) > 0,
    );
    if (later.isNotEmpty) {
      throw const ValidationException(
        'A later month is already closed — close months in order',
      );
    }
  }

  Future<MonthlyClosing?> closingForMonth(String month) =>
      cash.closingForMonth(month);

  Future<List<MonthlyClosing>> closings() => cash.closings();

  /// The closing figures for [month] without saving anything (actual = 0).
  Future<MonthlyClosing> preview(String month) async {
    final r = await report(from: monthFirstDay(month), to: monthLastDay(month));
    return MonthlyClosing(
      id: 'preview',
      month: month,
      openingBalance: r.openingBalance,
      cashReceived: r.cashReceived,
      commissionEarned: r.commissionEarned,
      commissionPaid: r.commissionPaid,
      rewardsPaid: r.rewardsPaid,
      otherPayments: r.otherPayments,
      otherIncome: r.otherIncome,
      expectedRemaining: r.closingBalance,
      actualCounted: 0,
      difference: 0,
      countedBy: '',
      createdAt: nowMs(),
    );
  }

  Future<MonthlyClosing> closeMonth({
    required String month,
    required int actualCounted,
    String note = '',
    required String countedBy,
  }) async {
    if (await cash.closingForMonth(month) != null) {
      throw const ValidationException('This month is already closed');
    }
    await _ensureInOrder(month);
    final p = await preview(month);
    final closing = MonthlyClosing(
      id: newId('close'),
      month: month,
      openingBalance: p.openingBalance,
      cashReceived: p.cashReceived,
      commissionEarned: p.commissionEarned,
      commissionPaid: p.commissionPaid,
      rewardsPaid: p.rewardsPaid,
      otherPayments: p.otherPayments,
      otherIncome: p.otherIncome,
      expectedRemaining: p.expectedRemaining,
      actualCounted: actualCounted,
      difference: actualCounted - p.expectedRemaining,
      note: note,
      countedBy: countedBy,
      createdAt: nowMs(),
    );
    await cash.insertClosing(closing);
    await audit.record(
      'MONTHLY_CLOSING',
      refId: closing.id,
      oldValue: 'expected ${closing.expectedRemaining}',
      newValue: 'actual $actualCounted (${closing.difference})',
    );
    return closing;
  }
}
