import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/dashboard_features.dart';
import 'package:lab_commission/main.dart';
import 'package:lab_commission/print/print_spool_watcher.dart';
import 'package:lab_commission/ui/admin_screens.dart';
import 'package:lab_commission/ui/dashboard_screen.dart';
import 'package:lab_commission/ui/scan_flow.dart';

/// Serves invoices straight from a stream controller: widget tests cannot do
/// real file I/O, and the real spool-folder polling is covered by
/// print_spool_test.dart.
class _FakeWatcher extends PrintSpoolWatcher {
  final _controller = StreamController<PrintedInvoice>.broadcast();

  @override
  Stream<PrintedInvoice> get invoices => _controller.stream;

  @override
  void start() {}

  @override
  bool get isRunning => true;

  @override
  String? get lastError => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _controller.close();
}

void main() {
  testWidgets('Login with staff PIN opens dashboard', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();

    expect(find.text('TWOK Sample Deli - Office'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('LOGIN'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dashboard'), findsOneWidget);
    // Staff see the fast receipt-capture entry point: the camera scanner on
    // mobile, the print monitor on Windows.
    expect(
      find.text(Platform.isWindows ? 'Print Monitor' : 'Scan Receipt'),
      findsOneWidget,
    );
  });

  testWidgets('Wrong PIN shows error and stays on login', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0000');
    await tester.tap(find.text('LOGIN'));
    await tester.pumpAndSettle();

    expect(find.text('Wrong PIN'), findsOneWidget);
    expect(find.text('TWOK Sample Deli - Office'), findsOneWidget);
  });

  testWidgets('Data-loading screens finish loading (no stuck spinner)', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('LOGIN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delivery History'));
    await tester.pumpAndSettle();

    expect(find.text('No deliveries recorded yet.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cash & Closing'));
    await tester.pumpAndSettle();

    expect(find.text('Remaining cash'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Adding a delivery man persists it', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('LOGIN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delivery Men'));
    await tester.pumpAndSettle();

    expect(find.text('No delivery men yet. Tap + to add.'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Ko Nay');
    await tester.enterText(fields.at(1), '0999');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Ko Nay'), findsOneWidget);
    expect(services.deliveryMen.all(), completion(hasLength(1)));
  });

  testWidgets('Reconciliation detailed results hide unclaimed barcodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    final users = await services.users.all();
    final adminId = users.firstWhere((u) => u.isAdmin).id;
    final staffId = users.firstWhere((u) => !u.isAdmin).id;
    final man = await services.deliveryMen.create(name: 'U Aung');

    // SCAN001 matches an official receipt; SCAN002 was scanned but never
    // imported; UNCLAIMED1 is an official receipt that was never scanned.
    for (final barcode in ['SCAN001', 'SCAN002']) {
      await services.delivery.recordCommission(
        barcode: barcode,
        deliveryManId: man.id,
        commission: 2000,
        staffUserId: staffId,
      );
    }
    await services.reconciliation.importOfficialReceipts([
      // A timed receipt whose commission was entered months later trips the
      // time-gap warning; UNCLAIMED1 stays out of the detail table.
      ['SCAN001', '2026-08-10 09:00', 75000],
      ['UNCLAIMED1', '2026-08-10', 75000],
    ]);
    await services.reconciliation.run(createdBy: adminId);

    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('LOGIN'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Reconciliation'));
    await tester.tap(find.text('Reconciliation'));
    await tester.pumpAndSettle();
    // Scanned barcodes are listed, whether matched or not found.
    expect(find.text('SCAN001'), findsOneWidget);
    expect(find.text('SCAN002'), findsOneWidget);
    // The never-scanned official receipt is excluded from the detail table.
    expect(find.text('UNCLAIMED1'), findsNothing);
    // Receipt/commission date-time columns with a time-gap status chip.
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Receipt Date/Time'), findsOneWidget);
    expect(find.text('Commission Date/Time'), findsOneWidget);
    expect(find.text('Time Gap'), findsOneWidget);
    expect(find.text('10/08/2026 09:00'), findsOneWidget);
    expect(find.textContaining('OVER'), findsWidgets);
  });

  testWidgets('Clear official receipts also clears reconciliation results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    final users = await services.users.all();
    final adminId = users.firstWhere((u) => u.isAdmin).id;
    final staffId = users.firstWhere((u) => !u.isAdmin).id;
    final man = await services.deliveryMen.create(name: 'U Aung');
    await services.delivery.recordCommission(
      barcode: 'CLR1',
      deliveryManId: man.id,
      commission: 2000,
      staffUserId: staffId,
    );
    await services.reconciliation.importOfficialReceipts([
      ['CLR1', '2026-08-10', 75000],
    ]);
    await services.reconciliation.run(createdBy: adminId);

    await tester.pumpWidget(LabCommissionApp(services: services));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('LOGIN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Receipt Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear official receipts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLEAR'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconciliation'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No reconciliation run yet.\nOfficial receipts must be imported first.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('A remembered session skips login, and logout forgets it', (
    tester,
  ) async {
    final storage = MemoryStorage();
    await (await AppServices.bootstrap(storage)).auth.login('1111');

    // Relaunch against the same database: straight to the dashboard.
    final relaunched = await AppServices.bootstrap(storage);
    await tester.pumpWidget(LabCommissionApp(services: relaunched));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dashboard'), findsOneWidget);
    expect(find.text('LOGIN'), findsNothing);

    // Logging out clears the remembered session for the next launch.
    await tester.tap(find.byTooltip('Logout'));
    await tester.pumpAndSettle();
    expect(find.text('TWOK Sample Deli - Office'), findsOneWidget);
    expect((await AppServices.bootstrap(storage)).auth.isLoggedIn, isFalse);
  });

  testWidgets('A QR-only delivery man needs an admin PIN to pick by hand', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await services.deliveryMen.create(name: 'Locked Man', requireQr: true);

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: SelectDeliveryManScreen(barcode: 'B1')),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> enterPin(String pin) async {
      await tester.enterText(find.widgetWithText(TextField, 'Admin PIN'), pin);
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
    }

    // Wrong PIN leaves the manual path locked.
    await tester.tap(find.text('Locked Man'));
    await tester.pumpAndSettle();
    await enterPin('0000');
    expect(find.text('Select Commission'), findsNothing);

    // A real admin PIN opens it.
    await tester.tap(find.text('Locked Man'));
    await tester.pumpAndSettle();
    await enterPin('1234');
    expect(find.text('Select Commission'), findsOneWidget);
  });

  testWidgets('a printed receipt opens the flow app-wide, not only on the '
      'monitor screen', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await services.auth.login('1111');
    final watcher = _FakeWatcher();
    addTearDown(watcher.dispose);

    await tester.pumpWidget(
      LabCommissionApp(
        services: services,
        loader: (_) async => services,
        printWatcher: watcher,
      ),
    );
    await tester.pumpAndSettle();

    // The user is on the dashboard — detection must not need the monitor
    // screen open.
    expect(find.textContaining('Dashboard'), findsOneWidget);

    watcher._controller.add(
      const PrintedInvoice(invoice: '001KHL0001234', name: 'Aye Chan'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectDeliveryManScreen), findsOneWidget);
    expect(find.textContaining('001KHL0001234'), findsWidgets);
    // The flow header shows who the sample belongs to.
    expect(find.text('Name:'), findsWidgets);
    expect(find.text('Aye Chan'), findsWidgets);
  });

  testWidgets('no flow opens from a print job before login', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final watcher = _FakeWatcher();
    addTearDown(watcher.dispose);

    await tester.pumpWidget(
      LabCommissionApp(
        services: services,
        loader: (_) async => services,
        printWatcher: watcher,
      ),
    );
    await tester.pumpAndSettle();

    watcher._controller.add(const PrintedInvoice(invoice: '001KHL0001234'));
    await tester.pumpAndSettle();

    expect(find.byType(SelectDeliveryManScreen), findsNothing);
    expect(find.text('TWOK Sample Deli - Office'), findsOneWidget);
    // The receipt itself is still kept for the history screens.
    expect(
      (await services.printedReceipts.byBarcode())['001KHL0001234'],
      isNotNull,
    );
  });

  testWidgets('a milestone reward earned on the recorded screen can be paid '
      'and un-paid there', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    await services.auth.login('1111');
    final staffId = services.auth.requireUser().id;
    final staffPin = (await services.dailyPins.currentPin(staffId))!;
    final man = await services.deliveryMen.create(name: 'Moe Thin');

    // The 10th delivery hits the seeded milestone rule (4,000 MMK).
    var tenth = await services.delivery.recordCommission(
      barcode: 'R1',
      deliveryManId: man.id,
      commission: 1000,
      staffUserId: staffId,
    );
    for (var i = 2; i <= 10; i++) {
      tenth = await services.delivery.recordCommission(
        barcode: 'R$i',
        deliveryManId: man.id,
        commission: 1000,
        staffUserId: staffId,
      );
    }
    final reward = tenth.rewards.single;

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: DeliverySuccessScreen(
            record: tenth.record,
            rewards: tenth.rewards,
            deliveryManName: man.name,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Freshly earned and unpaid: the card offers PAY straight away.
    expect(find.textContaining(' · unpaid'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(TextButton, 'PAY'));
    await tester.tap(find.widgetWithText(TextButton, 'PAY'));
    await tester.pumpAndSettle();

    // Paying asks for a confirmation before cash leaves the box.
    expect(find.text('Confirm payment'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Pay now'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reward paid'), findsOneWidget);
    expect(find.textContaining(' · paid'), findsOneWidget);
    expect(await services.cashService.balance(), -4000);
    expect(await services.cashService.rewardsPaid(), 4000);
    expect((await services.milestones.findReward(reward.id))!.isPaid, isTrue);
    expect(find.widgetWithText(TextButton, 'UNPAY'), findsOneWidget);

    // Let the confirmation snackbar expire before touching the card again.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(TextButton, 'UNPAY'));
    await tester.tap(find.widgetWithText(TextButton, 'UNPAY'));
    await tester.pumpAndSettle();

    // Taking the payment back needs today's PIN.
    expect(find.text('Daily PIN needed'), findsOneWidget);
    await tester.enterText(find.byType(TextField), staffPin);
    await tester.tap(find.widgetWithText(FilledButton, 'CONFIRM'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Reward un-paid'), findsOneWidget);
    expect(await services.cashService.balance(), 0);
    expect(await services.cashService.rewardsPaid(), 0);
    expect((await services.milestones.findReward(reward.id))!.isPaid, isFalse);
    expect(find.widgetWithText(TextButton, 'PAY'), findsOneWidget);

    // No snackbar timer may outlive the test.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('Admin Settings hides dashboard buttons per role', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: AdminSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // First checkbox in the Delivery Board row is the Staff column.
    final row = find
        .ancestor(of: find.text('Delivery Board'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(of: row, matching: find.byType(Checkbox)).first,
    );
    await tester.pumpAndSettle();
    expect(
      await services.settings.get(
        DashboardFeature.deliveryBoard.visibilityKey(admin: false),
      ),
      '0',
    );

    Future<void> showDashboard({required bool isAdmin}) async {
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: DashboardScreen(userName: 'Test', isAdmin: isAdmin),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await showDashboard(isAdmin: false);
    expect(find.text('Delivery Board'), findsNothing);
    expect(find.text('Delivery History'), findsOneWidget);

    // Hidden for staff only: admins still get the button.
    await showDashboard(isAdmin: true);
    expect(find.text('Delivery Board'), findsOneWidget);
  });
}
