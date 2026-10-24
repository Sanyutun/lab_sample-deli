import '../models/models.dart';
import '../storage/app_storage.dart';

/// Receipt fields captured from the print spooler, keyed by barcode.
///
/// This is a snapshot of what was printed, not a financial record: a reprint of
/// the same invoice refreshes the row instead of failing on the barcode key.
class PrintedReceiptRepository {
  PrintedReceiptRepository(this._storage);
  final AppStorage _storage;

  static const String table = 'printed_receipts';

  Future<void> save(PrintedReceipt receipt) async {
    final row = receipt.toMap();
    final existing = await _storage.findOne(table, {
      'barcode': receipt.barcode,
    });
    if (existing == null) {
      await _storage.insert(table, row);
    } else {
      // Already detected (a reprint), so refresh the fields instead.
      await _storage.update(table, {'barcode': receipt.barcode}, row);
    }
  }

  /// Every detected receipt, indexed by barcode for the list screens.
  Future<Map<String, PrintedReceipt>> byBarcode() async {
    final rows = await _storage.find(table);
    return {
      for (final m in rows) m['barcode'] as String: PrintedReceipt.fromMap(m),
    };
  }
}
