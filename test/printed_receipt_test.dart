import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/repositories/printed_receipt_repository.dart';
import 'package:lab_commission/data/storage/app_storage.dart';

void main() {
  test('a receipt is stored by barcode and a reprint refreshes it', () async {
    final repo = PrintedReceiptRepository(MemoryStorage());
    await repo.save(
      const PrintedReceipt(
        barcode: 'B1',
        patient: 'Aye Chan',
        ageSex: '34/F',
        refer: 'Dr. Lin',
        receiptDate: '18/10/2026 14:30',
        totalAmount: '75,000 MMK',
        detectedAt: 1,
      ),
    );
    await repo.save(
      const PrintedReceipt(
        barcode: 'B1',
        patient: 'Aye Chan',
        ageSex: '35/F',
        detectedAt: 2,
      ),
    );

    final all = await repo.byBarcode();
    expect(all, hasLength(1));
    expect(all['B1']!.ageSex, '35/F');
    expect(all['B1']!.detectedAt, 2);
    expect(all['B1']!.summary, contains('Patient: Aye Chan'));
    expect(all['B1']!.summary, isNot(contains('Refer:')));
  });

  test('the official export fills the fields the print job missed', () {
    final merged = receiptDetailsByBarcode(
      {
        'B1': const PrintedReceipt(
          barcode: 'B1',
          patient: 'Printed Name',
          detectedAt: 1,
        ),
      },
      {
        'B1': const OfficialReceipt(
          id: 'o1',
          barcode: 'B1',
          receiptDate: '2026-10-18',
          totalAmount: 75000,
          batchId: 'b1',
          importedAt: 1,
          patient: 'Official Name',
          refer: 'Dr. Lin',
        ),
      },
    );

    expect(merged['B1']!.patient, 'Printed Name');
    expect(merged['B1']!.refer, 'Dr. Lin');
    expect(merged['B1']!.receiptDate, '2026-10-18');
    expect(merged['B1']!.totalAmount, '75000');
  });
}
