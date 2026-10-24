import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/ui/delivery_routes_screen.dart';

Future<String> _staffId(AppServices services) async =>
    (await services.users.all()).firstWhere((u) => !u.isAdmin).id;

Future<void> _deliver(
  AppServices services,
  String manId,
  String barcode,
) async {
  await services.delivery.recordCommission(
    barcode: barcode,
    deliveryManId: manId,
    commission: 1000,
    staffUserId: await _staffId(services),
  );
}

/// The centre is the office; A1 was delivered about 100 m away, A2 about 9 km.
const String _centreLat = '16.80';
const String _centreLng = '96.20';

/// A man with two delivered routes: the near one first, the far one second.
Future<AppServices> _bootWithRoutes({bool withCentre = true}) async {
  final services = await AppServices.bootstrap(MemoryStorage());
  if (withCentre) {
    await services.settings.set('routeMap.centerLat', _centreLat);
    await services.settings.set('routeMap.centerLng', _centreLng);
  }
  final man = await services.deliveryMen.create(name: 'Ko Aung');
  final now = DateTime.now().millisecondsSinceEpoch;

  await services.companion.recordLocation(
    man.id,
    latitude: 16.801,
    longitude: 96.201,
    accuracyM: 8,
    capturedAt: now - 180000,
  );
  await _deliver(services, man.id, 'A1');

  await services.companion.recordLocation(
    man.id,
    latitude: 16.86,
    longitude: 96.26,
    accuracyM: 8,
    capturedAt: now - 60000,
  );
  await _deliver(services, man.id, 'A2');
  return services;
}

Future<void> _openDeliveryRoutes(
  WidgetTester tester,
  AppServices services,
) async {
  // The dashboard grid needs room for the whole tile list to be hit-testable.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // The dashboard tile is gone (Route Analysis replaces it), so the screen is
  // opened the same way the code still reaches it: directly, inside the app's
  // own scope so its services are available.
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: const MaterialApp(home: Scaffold(body: DeliveryRoutesScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every route, farthest from the centre first', (
    tester,
  ) async {
    final services = await _bootWithRoutes();
    await _openDeliveryRoutes(tester, services);

    // Both of the man's routes are offered, and the farthest one is drawn.
    expect(find.textContaining('A1 ·'), findsOneWidget);
    expect(find.textContaining('A2 ·'), findsOneWidget);
    expect(find.text('Receipt A2'), findsOneWidget);
    expect(find.byType(FlutterMap), findsOneWidget);

    // The headline number, the ranking, and where it was reached.
    expect(find.textContaining('Farthest from centre:'), findsOneWidget);
    expect(find.textContaining('route #1 of 2 by distance'), findsOneWidget);
    expect(find.textContaining('Reached at'), findsOneWidget);
  });

  testWidgets('selecting a route shows that one', (tester) async {
    final services = await _bootWithRoutes();
    await _openDeliveryRoutes(tester, services);

    await tester.tap(find.textContaining('A1 ·'));
    await tester.pumpAndSettle();

    expect(find.text('Receipt A1'), findsOneWidget);
    expect(find.text('Receipt A2'), findsNothing);
    // The near route is the second-farthest of the two.
    expect(find.textContaining('route #2 of 2 by distance'), findsOneWidget);
  });

  testWidgets('calls out the farthest point of all the man\'s routes', (
    tester,
  ) async {
    final services = await _bootWithRoutes();
    await _openDeliveryRoutes(tester, services);

    expect(
      find.textContaining('Farthest point of all routes:'),
      findsOneWidget,
    );
    // Its subtitle names the farthest route (A2, ~9 km out) and its point.
    expect(find.textContaining('· Receipt A2'), findsOneWidget);

    // Pick the near route; the headline still jumps back to the farthest.
    await tester.tap(find.textContaining('A1 ·'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt A1'), findsOneWidget);

    await tester.tap(find.textContaining('Farthest point of all routes:'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt A2'), findsOneWidget);
  });

  testWidgets('a changeable meter limit flags routes over it', (tester) async {
    final services = await _bootWithRoutes();
    await services.settings.set('routeMap.radiusM', '500');
    await _openDeliveryRoutes(tester, services);

    // Both stored routes hold both fixes (the late fix attached to A1 too),
    // so both are 9.22 km — headline, A1 row and A2 row all flag over 500 m.
    expect(find.text('OVER 500 m'), findsNWidgets(3));
    expect(find.textContaining('Over the 500 m limit'), findsOneWidget);
    expect(find.textContaining('limit 500 m'), findsOneWidget); // list caption

    // The limit can be changed later, right from this screen.
    await tester.tap(find.byTooltip('Distance limit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('OVER'), findsNothing);
    expect(find.textContaining('Within the 10.00 km limit'), findsOneWidget);
  });

  testWidgets('without a centre point the routes are listed but not measured', (
    tester,
  ) async {
    final services = await _bootWithRoutes(withCentre: false);
    await _openDeliveryRoutes(tester, services);

    expect(find.textContaining('A2 ·'), findsOneWidget);
    expect(find.textContaining('Centre point not set'), findsOneWidget);
    expect(find.textContaining('Farthest from centre:'), findsNothing);
    // Newest first is the only useful order without a centre.
    expect(find.textContaining('by distance'), findsNothing);
  });

  testWidgets('a delivery man with no routes says so', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await services.deliveryMen.create(name: 'Ko Aung');
    await _openDeliveryRoutes(tester, services);

    expect(
      find.textContaining('No routes were kept for Ko Aung'),
      findsOneWidget,
    );
  });
}
