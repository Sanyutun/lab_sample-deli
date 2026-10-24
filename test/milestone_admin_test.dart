import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/main.dart';

void main() {
  testWidgets('admin edits a milestone reward from Admin Settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final services = await AppServices.bootstrap(MemoryStorage());
    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('LOGIN'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Admin Settings'));
    await tester.tap(find.text('Admin Settings'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Every 10 deliveries'));
    await tester.tap(find.text('Every 10 deliveries'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Every N deliveries'),
      '5',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reward amount (MMK)'),
      '7000',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rule = (await services.milestones.rules()).firstWhere(
      (r) => r.everyN == 5,
    );
    expect(rule.rewardAmount, 7000);
    expect(find.text('Every 5 deliveries'), findsOneWidget);
    expect(find.text('7,000 MMK'), findsOneWidget);
  });
}
