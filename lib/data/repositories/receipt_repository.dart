import '../models/models.dart';
import '../storage/app_storage.dart';

class ReceiptRepository {
  ReceiptRepository(this._storage);
  final AppStorage _storage;

  static const String officialTable = 'official_receipts';
  static const String resultsTable = 'reconciliation_results';
  static const String runsTable = 'reconciliation_runs';

  Future<void> insertOfficial(OfficialReceipt receipt) async {
    await _storage.insert(officialTable, receipt.toMap());
  }

  Future<List<OfficialReceipt>> officialReceipts() async {
    final rows = await _storage.find(officialTable, orderBy: 'barcode');
    return rows.map(OfficialReceipt.fromMap).toList();
  }

  Future<List<OfficialReceipt>> officialByBarcode(String barcode) async {
    final rows = await _storage.find(
      officialTable,
      where: {'barcode': barcode},
    );
    return rows.map(OfficialReceipt.fromMap).toList();
  }

  /// Every imported official receipt, indexed by barcode for display.
  Future<Map<String, OfficialReceipt>> officialReceiptsByBarcode() async {
    final rows = await _storage.find(officialTable);
    return {for (final r in rows.map(OfficialReceipt.fromMap)) r.barcode: r};
  }

  Future<void> clearOfficial() async => _storage.clear(officialTable);

  /// Removes every reconciliation run and result, since they are derived from
  /// the official receipts.
  Future<void> clearReconciliation() async {
    await _storage.clear(resultsTable);
    await _storage.clear(runsTable);
  }

  // ---- reconciliation ----

  Future<void> insertRun(ReconciliationRun run) async {
    await _storage.insert(runsTable, run.toMap());
  }

  Future<List<ReconciliationRun>> runs() async {
    final rows = await _storage.find(runsTable, orderBy: '-created_at');
    return rows.map(ReconciliationRun.fromMap).toList();
  }

  Future<ReconciliationRun?> latestRun() async {
    final list = await runs();
    return list.isEmpty ? null : list.first;
  }

  Future<void> insertResults(List<ReconciliationResult> results) async {
    if (results.isEmpty) return;
    await _storage.insertMany(
      resultsTable,
      results.map((r) => r.toMap()).toList(),
    );
  }

  Future<List<ReconciliationResult>> resultsForRun(String runId) async {
    final rows = await _storage.find(resultsTable, where: {'run_id': runId});
    var list = rows.map(ReconciliationResult.fromMap).toList();
    // A run saved before the commission_at column existed has it null, which
    // leaves the detail table's Commission Date/Time blank. Fill it here from
    // the commission record, the same value a fresh run would store.
    if (list.any((r) => r.commissionAt == null)) {
      final byBarcode = <String, int>{
        for (final m in await _storage.find('commission_records'))
          m['barcode'] as String: (m['date_time'] as num).toInt(),
      };
      list = [
        for (final r in list)
          r.commissionAt != null || !byBarcode.containsKey(r.barcode)
              ? r
              : r.copyWith(commissionAt: byBarcode[r.barcode]),
      ];
    }
    list.sort((a, b) => a.barcode.compareTo(b.barcode));
    return list;
  }

  /// Most recent reconciliation outcome per barcode, across every run. Used by
  /// the companion app to show a reconciliation status next to a delivery.
  Future<Map<String, ReconciliationStatus>> latestStatusByBarcode() async {
    final rows = await _storage.find(resultsTable);
    final newest = <String, ReconciliationResult>{};
    for (final m in rows) {
      final r = ReconciliationResult.fromMap(m);
      final current = newest[r.barcode];
      if (current == null || r.createdAt >= current.createdAt) {
        newest[r.barcode] = r;
      }
    }
    return {for (final e in newest.entries) e.key: e.value.status};
  }
}
