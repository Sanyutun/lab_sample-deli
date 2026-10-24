import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/print/print_spool_watcher.dart';
import 'package:lab_commission/ui/print_monitor_screen.dart';
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
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _controller.close();

  @override
  bool get isRunning => true;

  @override
  String? get lastError => null;

  @override
  Future<void> get ready => Future<void>.value();
}

void main() {
  testWidgets('a detected print job is listed; the flow opens on demand', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final watcher = _FakeWatcher();
    addTearDown(watcher.dispose);

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(home: PrintMonitorScreen(watcher: watcher)),
      ),
    );

    // A print job arrives while the screen is watching.
    watcher._controller.add(
      const PrintedInvoice(
        invoice: '001KHL0001234',
        name: 'Aye Chan',
        ageSex: '34/F',
        refer: 'Dr. Lin',
        date: '12/05/2026',
        totalAmount: '75,000 MMK',
      ),
    );
    await tester.pumpAndSettle();

    // Auto-opening the flow belongs to the app-level listener (main.dart), so
    // detection keeps working after leaving this screen.
    expect(find.byType(SelectDeliveryManScreen), findsNothing);
    expect(find.text('001KHL0001234'), findsWidgets);
    // Every field read off the receipt is shown: label and value are separate
    // widgets so the values line up in their own column.
    expect(find.text('Name:'), findsWidgets);
    expect(find.text('Aye Chan'), findsWidgets);
    expect(find.text('Age/Sex:'), findsWidgets);
    expect(find.text('34/F'), findsWidgets);
    expect(find.text('Refer:'), findsWidgets);
    expect(find.text('Dr. Lin'), findsWidgets);
    expect(find.text('Date:'), findsWidgets);
    expect(find.text('12/05/2026'), findsWidgets);
    expect(find.text('Total Amount:'), findsWidgets);
    expect(find.text('75,000 MMK'), findsWidgets);
    // The list row summarises the receipt too.
    expect(find.textContaining('Age/Sex: 34/F'), findsOneWidget);

    // The flow still opens from here on demand, carrying the receipt details.
    await tester.tap(find.text('SELECT DELIVERY MAN'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectDeliveryManScreen), findsOneWidget);
    expect(find.text('Receipt: 001KHL0001234'), findsOneWidget);
    expect(find.text('Aye Chan'), findsWidgets);
    expect(find.text('Dr. Lin'), findsWidgets);
  });

  testWidgets('the receipt fields follow the flow to confirm', (tester) async {
    final services = await AppServices.bootstrap(MemoryStorage());

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(
          home: SelectDeliveryManScreen(
            barcode: '001KHL0001234',
            receipt: PrintedInvoice(
              invoice: '001KHL0001234',
              name: 'Aye Chan',
              ageSex: '34/F',
              refer: 'Dr. Lin',
              date: '12/05/2026',
              totalAmount: '75,000 MMK',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The fields are read off the receipt, not invented, so they show on the
    // picker itself.
    expect(find.text('34/F'), findsOneWidget);
    expect(find.text('75,000 MMK'), findsOneWidget);
  });

  testWidgets('a receipt total pre-selects the commission its rule expects', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final man = await services.deliveryMen.create(name: 'Aye Chan');

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: SelectCommissionScreen(
            barcode: '001KHL0001234',
            deliveryMan: man,
            receipt: const PrintedInvoice(
              invoice: '001KHL0001234',
              totalAmount: '75,000 MMK',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing was tapped: CONTINUE is already enabled with the answer from
    // the admin-settings rule for 75,000.
    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'CONTINUE'),
    );
    expect(continueButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'CONTINUE'));
    await tester.pumpAndSettle();
    // The confirm screen carries that amount through as the commission.
    expect(find.text('2,000 MMK'), findsOneWidget);
  });

  testWidgets('a receipt without a total still makes staff choose', (
    tester,
  ) async {
    final services = await AppServices.bootstrap(MemoryStorage());
    final man = await services.deliveryMen.create(name: 'Aye Chan');

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: SelectCommissionScreen(
            barcode: '001KHL0001234',
            deliveryMan: man,
            receipt: const PrintedInvoice(invoice: '001KHL0001234'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'CONTINUE'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.tap(find.widgetWithText(FilledButton, '3,000'));
    await tester.pumpAndSettle();
    final afterTap = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'CONTINUE'),
    );
    expect(afterTap.onPressed, isNotNull);
  });
}
