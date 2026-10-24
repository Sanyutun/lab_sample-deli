import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/ui/trip_history_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(
          home: TripHistoryScreen(barcode: 'R1', deliveryManName: 'Ko Aung'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a broken route says where the points are missing', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final staff = (await services.users.all()).firstWhere((u) => !u.isAdmin);
    final man = await services.deliveryMen.create(name: 'Ko Aung');
    final now = DateTime.now().millisecondsSinceEpoch;
    // Two fixes, 8 minutes apart, both inside the delivery's window; the second
    // one is poorly accurate.
    await services.companion.recordLocation(
      man.id,
      latitude: 16.84,
      longitude: 96.17,
      accuracyM: 8,
      capturedAt: now - 19 * 60 * 1000,
    );
    await services.companion.recordLocation(
      man.id,
      latitude: 16.85,
      longitude: 96.18,
      accuracyM: 90,
      capturedAt: now - 11 * 60 * 1000,
    );
    await services.delivery.recordCommission(
      barcode: 'R1',
      deliveryManId: man.id,
      commission: 1000,
      staffUserId: staff.id,
    );

    await pumpScreen(tester, services);

    expect(find.textContaining('Receipt R1'), findsOneWidget);
    expect(find.textContaining('2 point(s)'), findsOneWidget);
    expect(find.textContaining('1 gap(s) in the route'), findsOneWidget);
    expect(
      find.textContaining('1 point(s) had poor or unreported accuracy'),
      findsOneWidget,
    );
    // A gap is marked, never drawn as a travelled line.
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    // Each point shows its recorded time and accuracy.
    expect(find.textContaining('GPS accuracy ±8 m'), findsOneWidget);
    expect(find.textContaining('GPS accuracy ±90 m (poor)'), findsOneWidget);
    // The screen never claims the route proves the work.
    expect(
      find.textContaining('not proof that a test was done'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a receipt with no route is told plainly', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());

    await pumpScreen(tester, services);

    expect(
      find.textContaining('No route is available for this delivery'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.error_outline), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
