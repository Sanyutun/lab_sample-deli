import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/route_analysis.dart';
import 'package:lab_commission/main.dart';

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

/// One man, two deliveries: both about 9 km from the office, so both fall in
/// the default Zone C (5–10 km).
Future<AppServices> _bootWithRoutes() async {
  final services = await AppServices.bootstrap(MemoryStorage());
  await services.settings.set('routeMap.centerLat', '16.80');
  await services.settings.set('routeMap.centerLng', '96.20');
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

Future<void> _openRouteAnalysis(
  WidgetTester tester,
  AppServices services,
) async {
  // The dashboard grid needs room for the whole tile list to be hit-testable.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(LabCommissionApp(services: services));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '1234'); // admin
  await tester.tap(find.text('LOGIN'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Route Analysis'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('analyses deliveries into zones and filters the list', (
    tester,
  ) async {
    final services = await _bootWithRoutes();
    await _openRouteAnalysis(tester, services);

    // Both measured routes are listed with their distance and zone.
    expect(find.textContaining('A1 ·'), findsOneWidget);
    expect(find.textContaining('A2 ·'), findsOneWidget);
    expect(find.textContaining('farthest 9.'), findsNWidgets(2));
    expect(find.text('Zone summary'), findsOneWidget);
    expect(find.textContaining('2 valid route(s)'), findsOneWidget);

    // Both went ~9 km, so the whole valid set is Zone C.
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('Zone C'), findsWidgets);
    // The GPS jump between the two fixes is flagged, not smoothed over.
    expect(find.text('INCOMPLETE'), findsNWidgets(2));

    // The barcode filter narrows the list and the summary together.
    await tester.enterText(find.byType(TextField), 'A1');
    await tester.pumpAndSettle();
    expect(find.textContaining('A2 ·'), findsNothing);
    expect(find.textContaining('A1 ·'), findsOneWidget);
    expect(find.textContaining('1 valid route(s)'), findsOneWidget);

    // Clear restores both.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A2 ·'), findsOneWidget);
    expect(find.textContaining('2 valid route(s)'), findsOneWidget);
  });

  testWidgets('settings save the office centre and reject a zone gap', (
    tester,
  ) async {
    final services = await _bootWithRoutes();
    await _openRouteAnalysis(tester, services);

    await tester.tap(find.byTooltip('Route analysis settings'));
    await tester.pumpAndSettle();

    expect(find.text('Office / laboratory name'), findsOneWidget);
    expect(find.text('Distance zones'), findsOneWidget);
    expect(find.text('Zone A'), findsOneWidget);
    expect(find.text('Zone D'), findsOneWidget);

    // A name is required, so nothing is saved before one is entered.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'SAVE'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField).first, 'TWOK Lab');
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(await services.settings.get('routeMap.officeName'), 'TWOK Lab');
    // The centre and the default zones were saved too.
    expect(await services.settings.get('routeMap.centerLat'), '16.8');
    final saved = zonesFromJson(await services.settings.get('routeMap.zones'));
    expect(saved, hasLength(4));

    // Removing Zone B joins its 2–5 km band to Zone A: three zones, still
    // covering every distance, so the configuration stays saveable.
    await tester.tap(find.byTooltip('Delete zone').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Zone B'), findsNothing);
    expect(find.text('Zone A'), findsOneWidget);
    expect(find.text('Zone C'), findsOneWidget);
    // Zone A's own range now covers what Zone B used to.
    expect(find.text('0–5 km'), findsOneWidget);
    expect(find.textContaining('Gap between'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'SAVE'))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(
      zonesFromJson(await services.settings.get('routeMap.zones')),
      hasLength(3),
    );

    // Typing a contradictory range is still refused, with the reason shown.
    // (The list's edit buttons carry no tooltip, so find them by icon.)
    await tester.tap(find.byIcon(Icons.edit).at(1)); // Zone C
    await tester.pumpAndSettle();
    expect(find.textContaining('Edit Zone C'), findsOneWidget);
    // The dialog's own fields, not the page's: name, min, then max.
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogFields, findsNWidgets(3));
    final saveButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Save'),
    );
    expect(saveButton, findsOneWidget);
    await tester.enterText(dialogFields.at(1), '30'); // min km
    await tester.pump();
    await tester.enterText(dialogFields.at(2), '20'); // max km
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Maximum must be greater'), findsOneWidget);
    expect(find.text('Edit Zone C'), findsOneWidget); // the dialog stayed open
  });
}
