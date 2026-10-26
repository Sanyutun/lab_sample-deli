import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/domain/ids.dart';
import 'package:lab_commission/domain/period.dart';
import 'package:lab_commission/ui/finance_screen.dart';

void main() {
  testWidgets('Closing a month requires the admin PIN', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final services = await AppServices.bootstrap(MemoryStorage());
    await services.auth.login('1234');
    final month = monthOfIso(todayIso());

    await tester.pumpWidget(
      AppScope(
        services: services,
        child: const MaterialApp(home: FinanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '100000');
    await tester.tap(find.text('CLOSE MONTH'));
    await tester.pumpAndSettle();

    expect(find.text('Admin PIN'), findsOneWidget);

    // Cancelling leaves the month open.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await services.finance.closingForMonth(month), isNull);

    // The right PIN submits the closing.
    await tester.tap(find.text('CLOSE MONTH'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(await services.finance.closingForMonth(month), isNotNull);
    expect(find.textContaining('Month closed'), findsOneWidget);
  });
}
