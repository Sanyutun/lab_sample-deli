import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/models/models.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/ui/history_screens.dart';

CommissionRecord _rec(String id, DateTime dt, {String man = 'dm1'}) =>
    CommissionRecord(
      id: id,
      barcode: id,
      deliveryManId: man,
      commission: 1000,
      dateTime: dt.millisecondsSinceEpoch,
      staffUserId: 's1',
      createdAt: dt.millisecondsSinceEpoch,
    );

void main() {
  test('filterDeliveries keeps the man and whole calendar days', () {
    final records = [
      _rec('before', DateTime(2026, 10, 9, 23, 59), man: 'm1'),
      _rec('first', DateTime(2026, 10, 10), man: 'm1'),
      _rec('middle', DateTime(2026, 10, 11, 12), man: 'm2'),
      _rec('last', DateTime(2026, 10, 12, 23, 59), man: 'm1'),
      _rec('after', DateTime(2026, 10, 13, 0, 1), man: 'm1'),
    ];
    final range = DateTimeRange(
      start: DateTime(2026, 10, 10),
      end: DateTime(2026, 10, 12),
    );
    expect(filterDeliveries(records, range: range).map((r) => r.id), [
      'first',
      'middle',
      'last',
    ]);
    expect(filterDeliveries(records, deliveryManId: 'm2').map((r) => r.id), [
      'middle',
    ]);
    expect(
      filterDeliveries(
        records,
        deliveryManId: 'm1',
        range: range,
      ).map((r) => r.id),
      ['first', 'last'],
    );
  });

  testWidgets('Delivery History filters by delivery man', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await services.auth.login('1111');
    final staffId = services.auth.requireUser().id;
    final aung = await services.deliveryMen.create(name: 'Aung Aung');
    final moe = await services.deliveryMen.create(name: 'Moe Moe');
    await services.receipts.insertOfficial(
      const OfficialReceipt(
        id: 'o1',
        barcode: 'A1',
        receiptDate: '2026-10-18',
        totalAmount: 75000,
        batchId: 'b1',
        importedAt: 1,
        patient: 'Daw Hla',
        refer: 'Dr. Lin',
      ),
    );
    await services.delivery.recordCommission(
      barcode: 'A1',
      deliveryManId: aung.id,
      commission: 1000,
      staffUserId: staffId,
    );
    await services.delivery.recordCommission(
      barcode: 'B1',
      deliveryManId: moe.id,
      commission: 2000,
      staffUserId: staffId,
    );

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: DeliveryHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('A1'), findsOneWidget);
    expect(find.textContaining('B1'), findsOneWidget);
    // The official export imported for reconciliation fills in the details
    // when the receipt was not detected from a print job.
    expect(find.textContaining('Patient: Daw Hla'), findsOneWidget);
    expect(find.textContaining('Refer: Dr. Lin'), findsOneWidget);

    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moe Moe').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('B1'), findsOneWidget);
    expect(find.textContaining('A1'), findsNothing);
  });

  testWidgets('Staff see deliveries entered by another user', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final admin = (await services.users.all()).firstWhere((u) => u.isAdmin);
    await services.auth.login('1111');
    final man = await services.deliveryMen.create(name: 'Aung Aung');
    await services.delivery.recordCommission(
      barcode: 'C1',
      deliveryManId: man.id,
      commission: 1000,
      staffUserId: admin.id,
    );

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: DeliveryHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(services.auth.isAdmin, isFalse);
    expect(find.textContaining('C1'), findsOneWidget);
    expect(find.text('No deliveries recorded yet.'), findsNothing);
  });
}
