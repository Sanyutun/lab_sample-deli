import '../models/models.dart';
import '../storage/app_storage.dart';
import '../../domain/ids.dart';

class CashRepository {
  CashRepository(this._storage);
  final AppStorage _storage;

  static const String advancesTable = 'cash_advances';
  static const String txnsTable = 'cash_transactions';
  static const String closingsTable = 'monthly_closings';

  // ---- advances ----

  Future<CashAdvance> insertAdvance({
    required String date,
    required int amount,
    String note = '',
    required String createdBy,
  }) async {
    final advance = CashAdvance(
      id: newId('adv'),
      date: date,
      amount: amount,
      note: note,
      createdBy: createdBy,
      createdAt: nowMs(),
    );
    await _storage.insert(advancesTable, advance.toMap());
    return advance;
  }

  Future<List<CashAdvance>> advances() async {
    final rows = await _storage.find(advancesTable, orderBy: '-date');
    return rows.map(CashAdvance.fromMap).toList();
  }

  // ---- ledger ----

  Future<CashTransaction> insertTxn({
    required CashTxnType type,
    required int amount,
    String? refType,
    String? refId,
    String? date,
    String note = '',
    required String createdBy,
  }) async {
    final txn = CashTransaction(
      id: newId('ctx'),
      type: type,
      amount: amount,
      refType: refType,
      refId: refId,
      date: date ?? todayIso(),
      note: note,
      createdBy: createdBy,
      createdAt: nowMs(),
    );
    await _storage.insert(txnsTable, txn.toMap());
    return txn;
  }

  Future<List<CashTransaction>> ledger() async {
    final rows = await _storage.find(txnsTable, orderBy: '-date');
    return rows.map(CashTransaction.fromMap).toList();
  }

  Future<int> balance({String? throughDate}) async {
    final rows = await _storage.find(txnsTable);
    final txns = rows.map(CashTransaction.fromMap).toList();
    int total = 0;
    for (final t in txns) {
      if (throughDate == null || t.date.compareTo(throughDate) <= 0) {
        total += t.amount;
      }
    }
    return total;
  }

  Future<bool> hasTxnFor(String refId) async {
    final rows = await _storage.find(txnsTable, where: {'ref_id': refId});
    return rows.isNotEmpty;
  }

  /// Signed sum of all ledger entries linked to [refId]. A value of 0 means the
  /// net cash effect has been fully settled (e.g. a payment was un-paid).
  Future<int> netFor(String refId) async {
    final rows = await _storage.find(txnsTable, where: {'ref_id': refId});
    var total = 0;
    for (final r in rows) {
      total += (r['amount'] as num).toInt();
    }
    return total;
  }

  // ---- closings ----

  Future<void> insertClosing(MonthlyClosing closing) async {
    await _storage.insert(closingsTable, closing.toMap());
  }

  Future<MonthlyClosing?> closingForMonth(String month) async {
    final m = await _storage.findOne(closingsTable, {'month': month});
    return m == null ? null : MonthlyClosing.fromMap(m);
  }

  Future<List<MonthlyClosing>> closings() async {
    final rows = await _storage.find(closingsTable, orderBy: '-month');
    return rows.map(MonthlyClosing.fromMap).toList();
  }
}
