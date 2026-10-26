import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/ui/admin_screens.dart';

void main() {
  Future<AppServices> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    await services.auth.login('1234');
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: AdminSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return services;
  }

  testWidgets('admin adds a commission rule, overlap is refused in place', (
    tester,
  ) async {
    final services = await pumpSettings(tester);

    // Make room above the seeded top band first; bands may not overlap.
    await tester.ensureVisible(find.text('100,001 MMK – ∞'));
    await tester.tap(find.text('100,001 MMK – ∞'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Max receipt total (empty = no limit)'),
      '200000',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('100,001 MMK – 200,000 MMK'), findsOneWidget);

    await tester.ensureVisible(find.text('ADD RULE'));
    await tester.tap(find.text('ADD RULE'));
    await tester.pumpAndSettle();

    expect(find.text('New commission rule'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Min receipt total'),
      '150000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Commission amount'),
      '4500',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The overlapping band is refused and the dialog keeps the numbers.
    expect(find.textContaining('Overlaps'), findsOneWidget);
    expect(find.text('New commission rule'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Min receipt total'),
      '200001',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final added = (await services.commissions.rules()).firstWhere(
      (r) => r.minAmount == 200001,
    );
    expect(added.maxAmount, isNull);
    expect(added.commissionAmount, 4500);
    expect(added.active, isTrue);
    expect(find.text('200,001 MMK – ∞'), findsOneWidget);
    expect(
      (await services.audit.logs()).where(
        (l) => l.action == 'COMMISSION_RULE_ADDED',
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'admin adds a milestone reward rule, duplicate count is refused',
    (tester) async {
      final services = await pumpSettings(tester);

      await tester.ensureVisible(find.text('ADD REWARD RULE'));
      await tester.tap(find.text('ADD REWARD RULE'));
      await tester.pumpAndSettle();

      expect(find.text('New milestone reward'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Every N deliveries'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reward amount (MMK)'),
        '8000',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // The seeded every-10 rule is already there.
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(find.text('New milestone reward'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Every N deliveries'),
        '25',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final added = (await services.milestones.rules()).firstWhere(
        (r) => r.everyN == 25,
      );
      expect(added.rewardAmount, 8000);
      expect(added.active, isTrue);
      expect(find.text('Every 25 deliveries'), findsOneWidget);
      expect(find.text('8,000 MMK'), findsOneWidget);
      expect(
        (await services.audit.logs()).where(
          (l) => l.action == 'MILESTONE_RULE_ADDED',
        ),
        hasLength(1),
      );
    },
  );
}
