import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/ui/location_map_screen.dart';

void main() {
  testWidgets('Delivery Map plots the newest fix per delivery man', (
    tester,
  ) async {
    // The dashboard grid needs room for the whole tile list to be hit-testable.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    final man = await services.deliveryMen.create(name: 'Ko Aung');
    // Older fix, then newer: only the newer one belongs on the map.
    await services.companion.recordLocation(
      man.id,
      latitude: 16.80,
      longitude: 96.20,
      accuracyM: 30,
      capturedAt: 1000,
    );
    await services.companion.recordLocation(
      man.id,
      latitude: 16.81,
      longitude: 96.21,
      accuracyM: 12,
      capturedAt: 2000,
    );

    // The dashboard tile is gone, so the screen is opened directly, inside the
    // app's own scope so its services are available.
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: Scaffold(body: LocationMapScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No GPS fixes yet'), findsNothing);
    expect(find.text('K'), findsOneWidget);

    await tester.tap(find.text('K'));
    await tester.pumpAndSettle();

    expect(find.text('Ko Aung'), findsOneWidget);
    expect(find.textContaining('about 12 m'), findsOneWidget);

    // Drop the tree so the refresh timer is cancelled before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
