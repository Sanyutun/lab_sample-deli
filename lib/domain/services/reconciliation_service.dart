import '../../data/models/models.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/delivery_man_repository.dart';
import '../../data/repositories/receipt_repository.dart';
import '../exceptions.dart';
import '../ids.dart';
import 'audit_service.dart';

class ImportReport {
  const ImportReport({
    required this.imported,
    required this.duplicates,
    this.duplicateBarcodes = const [],
  });
  final int imported;

  /// Number of distinct barcodes that were already imported by an earlier file
  /// or repeated inside this one.
  final int duplicates;
  final List<String> duplicateBarcodes;
}

/// Parses official receipt export files (CSV / Excel) into rows.
///
/// The receipt-software export is laid out with the column names on the 3rd
/// row and uses columns such as `Invoice` (or `Invoice No`) for the receipt
/// number (barcode), `Date` + `Time`, `Refer`/`Refer By` for who referred it,
/// `Patient`/`Patient Name` for the patient, and `Net amt` for the total.
class OfficialReceiptParser {
  static const List<String> barcodeKeys = [
    'barcode',
    'receipt no',
    'receipt no.',
    'receipt number',
    'receipt',
    'rcpt no',
    'invoice',
    'invoice no',
    'invoice no.',
    'invoice number',
  ];
  static const List<String> dateKeys = [
    'date',
    'receipt date',
    'rcpt date',
    'invoice date',
  ];
  static const List<String> timeKeys = [
    'time',
    'time in',
    'time out',
    'invoice time',
    'receipt time',
    'rcpt time',
  ];
  static const List<String> referKeys = ['refer', 'refer by'];
  static const List<String> patientKeys = [
    'patient',
    'patient name',
    'pt name',
    'name',
    'customer',
    'customer name',
  ];
  static const List<String> amountKeys = [
    'total',
    'amount',
    'total amount',
    'receipt total',
    'total amt',
    'grand total',
    'net',
    'net amt',
    'net amount',
  ];

  /// Rows: [barcode, receiptDate(yyyy-MM-dd[ HH:mm]), totalAmount, refer,
  /// patient]
  ///
  /// When a `Time` column exists in addition to `Date`, the stored date keeps
  /// the time too (`yyyy-MM-dd HH:mm`).
  static List<List<Object>> parse(String filename, List<List<dynamic>> rows) {
    if (rows.isEmpty) throw const ValidationException('File is empty');
    final headerIndex = _findHeaderRow(rows);
    if (headerIndex < 0) {
      throw const ValidationException(
        'Header row with barcode column not found',
      );
    }
    final header = _headerOf(rows[headerIndex]);

    final barcodeCol = _findBarcodeCol(header) ?? 0;
    final dateCol = _findDateCol(header);
    final timeCol = _findTimeCol(header);
    final amountCol = _findAmountCol(header) ?? 0;
    final referCol = _findReferCol(header);
    final patientCol = _findPatientCol(header);

    final out = <List<Object>>[];
    for (var r = headerIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;
      final barcode = _cellText(row, barcodeCol);
      if (barcode.isEmpty || _isFooterRow(barcode)) continue;
      final date = _toDate(_cell(row, dateCol));
      final time = _toTime(_cell(row, timeCol));
      final amount = _toInt(_cell(row, amountCol)) ?? 0;
      final refer = _cellText(row, referCol);
      final patient = _cellText(row, patientCol);
      out.add([
        barcode,
        time == null ? date : '$date $time',
        amount,
        refer,
        patient,
      ]);
    }
    if (out.isEmpty) {
      throw const ValidationException('No data rows found in file');
    }
    return out;
  }

  /// The column names sit on the 3rd row of the receipt-software export, but
  /// scanning the first rows keeps it safe for plain CSV/Excel files too.
  static int _findHeaderRow(List<List<dynamic>> rows) {
    int? fallback;
    for (var i = 0; i < rows.length && i < 10; i++) {
      final h = _headerOf(rows[i]);
      if (_findBarcodeCol(h) == null) continue;
      fallback ??= i;
      if (_findDateCol(h) != null && _findAmountCol(h) != null) return i;
    }
    return fallback ?? -1;
  }

  static List<String> _headerOf(List<dynamic> row) =>
      row.map((e) => e.toString().trim().toLowerCase()).toList();

  static int? _findBarcodeCol(List<String> h) {
    // A column named just "No" is almost always the row serial number, not the
    // receipt number. Prefer an explicit invoice/receipt/barcode column and only
    // fall back to "No" when nothing else names the receipt.
    var bareNo = -1;
    for (var i = 0; i < h.length; i++) {
      if (barcodeKeys.contains(h[i]) ||
          h[i].contains('invoice') ||
          h[i].contains('rcpt no') ||
          h[i].contains('receipt no')) {
        return i;
      }
      if (bareNo < 0 && h[i] == 'no') bareNo = i;
    }
    return bareNo >= 0 ? bareNo : null;
  }

  static int? _findDateCol(List<String> h) {
    for (var i = 0; i < h.length; i++) {
      if (dateKeys.contains(h[i])) return i;
      if (h[i] == 'date' || h[i].endsWith(' date')) return i;
    }
    return null;
  }

  static int? _findTimeCol(List<String> h) {
    for (var i = 0; i < h.length; i++) {
      if (timeKeys.contains(h[i])) return i;
      if (h[i].endsWith('time')) return i;
    }
    return null;
  }

  static int? _findAmountCol(List<String> h) {
    for (var i = 0; i < h.length; i++) {
      if (amountKeys.contains(h[i])) return i;
      if (h[i].contains('amt') || h[i].contains('net')) return i;
    }
    return null;
  }

  static int? _findReferCol(List<String> h) {
    for (var i = 0; i < h.length; i++) {
      if (referKeys.contains(h[i]) || h[i].startsWith('refer ')) return i;
    }
    return null;
  }

  static int? _findPatientCol(List<String> h) {
    int? patientCol;
    for (var i = 0; i < h.length; i++) {
      if (patientKeys.contains(h[i])) return i;
      if (h[i].contains('patient')) {
        if (h[i].contains('name')) return i;
        patientCol ??= i;
      }
    }
    return patientCol;
  }

  static Object? _cell(List<dynamic> row, int? col) =>
      (col != null && col >= 0 && col < row.length) ? row[col] : null;

  /// Text for a column, normalising Excel numeric cells (125000.0 -> 125000).
  static String _cellText(List<dynamic> row, int? col) {
    final v = _cell(row, col);
    if (v == null) return '';
    if (v is num) return v.toInt().toString();
    return v.toString();
  }

  /// Skips echoed header cells and totals/subtotal footer rows.
  static bool _isFooterRow(String s) {
    final t = s.toLowerCase();
    if (t == 'barcode' || t == 'invoice' || t == 'invoice no') return true;
    return t.contains('total');
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    final s = v.toString().replaceAll(RegExp(r'[,\s]'), '');
    return int.tryParse(s) ?? (double.tryParse(s)?.round());
  }

  static String _toDate(dynamic v) {
    if (v == null || v.toString().trim().isEmpty) return todayIso();
    if (v is num) {
      // Excel serial date
      final epoch = DateTime.utc(1899, 12, 30).add(Duration(days: v.toInt()));
      return '${epoch.year.toString().padLeft(4, '0')}-${epoch.month.toString().padLeft(2, '0')}-${epoch.day.toString().padLeft(2, '0')}';
    }
    final s = v.toString().trim();
    final dmy = RegExp(r'^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})$')
        .firstMatch(s);
    if (dmy != null) {
      final day = int.parse(dmy.group(1)!);
      final month = int.parse(dmy.group(2)!);
      final year = int.parse(dmy.group(3)!);
      return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }
    final ymd = RegExp(r'^(\d{4})[\/\-\.](\d{1,2})[\/\-\.](\d{1,2})')
        .firstMatch(s);
    if (ymd != null) {
      final year = int.parse(ymd.group(1)!);
      final month = int.parse(ymd.group(2)!);
      final day = int.parse(ymd.group(3)!);
      return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    }
    final parsed = DateTime.tryParse(s);
    if (parsed != null) {
      return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    }
    return todayIso();
  }

  static String? _toTime(dynamic v) {
    if (v == null || v.toString().trim().isEmpty) return null;
    if (v is num && v >= 0 && v < 1) {
      // Excel serial time (fraction of a day)
      final totalMin = (v * 24 * 60).round();
      final hh = (totalMin ~/ 60).toString().padLeft(2, '0');
      final mm = (totalMin % 60).toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    final m = RegExp(
      r'(\d{1,2}):(\d{2})\s*(am|pm)?',
      caseSensitive: false,
    ).firstMatch(v.toString().trim());
    if (m != null) {
      var hh = int.parse(m.group(1)!);
      final mm = m.group(2)!;
      if ((m.group(3) ?? '').toLowerCase() == 'pm' && hh < 12) hh += 12;
      return '${hh.toString().padLeft(2, '0')}:$mm';
    }
    return null;
  }
}

class ReconciliationService {
  ReconciliationService({
    required this.receipts,
    required this.commissions,
    required this.deliveryMen,
    required this.audit,
  });

  final ReceiptRepository receipts;
  final CommissionRepository commissions;
  final DeliveryManRepository deliveryMen;
  final AuditService audit;

  /// Import official receipt rows: [barcode, receiptDate, totalAmount, refer?,
  /// patient?].
  ///
  /// A receipt-software export writes one row per test item, so the same
  /// invoice (barcode) repeats. Rows sharing a barcode are merged into one
  /// receipt and their amounts summed. A barcode already stored by an earlier
  /// import is reported and skipped, so re-importing a file cannot double the
  /// receipts and mark every row as a duplicate in reconciliation.
  Future<ImportReport> importOfficialReceipts(List<List<Object>> rows) async {
    final batchId = newId('batch');
    final existing = <String>{
      for (final o in await receipts.officialReceipts()) o.barcode,
    };

    // [receiptDate, totalAmount, refer, patient] per barcode.
    final grouped = <String, List<Object>>{};
    for (final row in rows) {
      final barcode = row[0].toString().trim();
      if (barcode.isEmpty) continue;
      final date = row[1].toString();
      final amount = row[2] is int
          ? row[2] as int
          : int.tryParse(row[2].toString()) ?? 0;
      final refer = row.length > 3 ? row[3].toString().trim() : '';
      final patient = row.length > 4 ? row[4].toString().trim() : '';
      final item = grouped[barcode];
      if (item == null) {
        grouped[barcode] = [date, amount, refer, patient];
      } else {
        item[1] = (item[1] as int) + amount;
        if ((item[0] as String).isEmpty) item[0] = date;
        if ((item[2] as String).isEmpty) item[2] = refer;
        if ((item[3] as String).isEmpty) item[3] = patient;
      }
    }

    final duplicateBarcodes = <String>{};
    var imported = 0;
    for (final entry in grouped.entries) {
      if (existing.contains(entry.key)) {
        duplicateBarcodes.add(entry.key);
        continue;
      }
      final item = entry.value;
      await receipts.insertOfficial(
        OfficialReceipt(
          id: newId('off'),
          barcode: entry.key,
          receiptDate: item[0] as String,
          totalAmount: item[1] as int,
          refer: item[2] as String,
          patient: item[3] as String,
          batchId: batchId,
          importedAt: nowMs(),
        ),
      );
      imported++;
    }
    await audit.record(
      'OFFICIAL_RECEIPTS_IMPORTED',
      newValue:
          '$imported receipts (${duplicateBarcodes.length} already imported, skipped) batch $batchId',
    );
    return ImportReport(
      imported: imported,
      duplicates: duplicateBarcodes.length,
      duplicateBarcodes: duplicateBarcodes.toList(),
    );
  }

  Future<ReconciliationRun> run({required String createdBy}) async {
    final staffRecords = await commissions.all(status: RecordStatus.active);
    final official = await receipts.officialReceipts();
    // Load the small reference datasets once instead of re-querying them for
    // every row (rules + delivery-man names). This keeps the run O(n) instead
    // of issuing thousands of extra database queries on large imports.
    final rules = await commissions.rules(activeOnly: true);
    final manNames = <String, String>{
      for (final man in await deliveryMen.all()) man.id: man.name,
    };

    int? expectedFor(int total) {
      for (final rule in rules) {
        if (rule.matches(total)) return rule.commissionAmount;
      }
      return null;
    }

    final officialByBarcode = <String, List<OfficialReceipt>>{};
    for (final o in official) {
      (officialByBarcode[o.barcode] ??= []).add(o);
    }
    final staffByBarcode = <String, List<CommissionRecord>>{};
    for (final s in staffRecords) {
      (staffByBarcode[s.barcode] ??= []).add(s);
    }

    final runId = newId('rec');
    final results = <ReconciliationResult>[];
    var match = 0, mismatch = 0, notFound = 0, duplicate = 0;

    for (final record in staffRecords) {
      final officialRows = officialByBarcode[record.barcode];
      final officialReceipt = (officialRows?.isNotEmpty ?? false)
          ? officialRows!.first
          : null;

      final ReconciliationStatus status;
      if ((staffByBarcode[record.barcode]?.length ?? 0) > 1) {
        status = ReconciliationStatus.duplicateStaff;
      } else if (officialRows == null || officialRows.isEmpty) {
        status = ReconciliationStatus.notFound;
      } else if (officialRows.length > 1) {
        status = ReconciliationStatus.duplicateOfficial;
      } else {
        final expected = expectedFor(officialRows.first.totalAmount);
        status = (expected != null && expected == record.commission)
            ? ReconciliationStatus.match
            : ReconciliationStatus.mismatch;
      }

      switch (status) {
        case ReconciliationStatus.match:
          match++;
        case ReconciliationStatus.mismatch:
          mismatch++;
        case ReconciliationStatus.notFound:
          notFound++;
        case ReconciliationStatus.duplicateStaff:
        case ReconciliationStatus.duplicateOfficial:
          duplicate++;
        default:
          break;
      }
      results.add(
        ReconciliationResult(
          id: newId('res'),
          runId: runId,
          barcode: record.barcode,
          receiptAmount: officialReceipt?.totalAmount,
          deliveryManId: record.deliveryManId,
          enteredCommission: record.commission,
          expectedCommission: officialReceipt == null
              ? null
              : expectedFor(officialReceipt.totalAmount),
          status: status,
          createdAt: nowMs(),
          deliveryManName:
              manNames[record.deliveryManId] ?? record.deliveryManId,
          receiptDate: officialReceipt?.receiptDate,
          refer: officialReceipt?.refer ?? '',
          patient: officialReceipt?.patient ?? '',
          commissionAt: record.dateTime,
        ),
      );
    }

    var unclaimed = 0;
    for (final entry in officialByBarcode.entries) {
      if (staffByBarcode.containsKey(entry.key)) continue;
      final duplicated = entry.value.length > 1;
      for (final o in entry.value) {
        if (duplicated) {
          duplicate++;
        } else {
          unclaimed++;
        }
        results.add(
          ReconciliationResult(
            id: newId('res'),
            runId: runId,
            barcode: o.barcode,
            receiptAmount: o.totalAmount,
            expectedCommission: expectedFor(o.totalAmount),
            status: duplicated
                ? ReconciliationStatus.duplicateOfficial
                : ReconciliationStatus.unclaimed,
            createdAt: nowMs(),
            receiptDate: o.receiptDate,
            refer: o.refer,
            patient: o.patient,
          ),
        );
      }
    }

    final run = ReconciliationRun(
      id: runId,
      officialCount: official.length,
      staffCount: staffRecords.length,
      matchCount: match,
      mismatchCount: mismatch,
      notFoundCount: notFound,
      duplicateCount: duplicate,
      unclaimedCount: unclaimed,
      createdBy: createdBy,
      createdAt: nowMs(),
    );
    await receipts.insertRun(run);
    await receipts.insertResults(results);
    await audit.record(
      'RECONCILIATION_RUN',
      refId: runId,
      newValue:
          'official ${run.officialCount} staff ${run.staffCount} match $match mismatch $mismatch notFound $notFound dup $duplicate unclaimed $unclaimed',
    );
    return run;
  }

  Future<(ReconciliationRun?, List<ReconciliationResult>)> latest() async {
    final run = await receipts.latestRun();
    if (run == null) return (null, <ReconciliationResult>[]);
    return (run, await receipts.resultsForRun(run.id));
  }

  Future<List<OfficialReceipt>> officialReceipts() =>
      receipts.officialReceipts();

  Future<int> officialCount() async =>
      (await receipts.officialReceipts()).length;
}
