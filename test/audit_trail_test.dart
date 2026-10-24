import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/ui/history_screens.dart';

Future<AppServices> _services(String pin) async {
  final services = await AppServices.bootstrap(MemoryStorage());
  await services.auth.login(pin);
  return services;
}

Future<String> _record(AppServices services, String barcode) async {
  final man = await services.deliveryMen.create(name: 'Aung Aung');
  final result = await services.delivery.recordCommission(
    barcode: barcode,
    deliveryManId: man.id,
    commission: 1000,
    staffUserId: services.auth.requireUser().id,
  );
  await services.cashService.payCommission(
    recordId: result.record.id,
    staffUserId: services.auth.requireUser().id,
  );
  return result.record.id;
}

void main() {
  test('audit logs can be read for one record only', () async {
    final services = await _services('1111');
    final first = await _record(services, 'A1');
    await _record(services, 'B1');

    final logs = await services.audit.logsFor(first);

    expect(
      logs.map((l) => l.action),
      containsAll(['COMMISSION_RECORDED', 'COMMISSION_PAID']),
    );
    expect(logs.every((l) => l.refId == first), isTrue);
  });

  testWidgets('Delivery History opens the audit trail on tap', (tester) async {
    final services = await _services('1111');
    await _record(services, 'A1');

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: DeliveryHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('A1').first);
    await tester.pumpAndSettle();

    expect(find.text('Audit trail'), findsOneWidget);
    expect(find.text('COMMISSION_RECORDED'), findsOneWidget);
    expect(find.text('COMMISSION_PAID'), findsOneWidget);
  });

  testWidgets('Commission History opens the audit trail on tap', (
    tester,
  ) async {
    final services = await _services('1234');
    await _record(services, 'A1');

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: CommissionHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('A1').first);
    await tester.pumpAndSettle();

    expect(find.text('Audit trail'), findsOneWidget);
    expect(find.text('COMMISSION_RECORDED'), findsOneWidget);
  });
}
