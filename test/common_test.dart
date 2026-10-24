import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/ui/common.dart';

void main() {
  testWidgets('AutoGrid gains columns as the available width grows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<int> columnsAt(double width) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          // Align loosens the root's tight constraints so the SizedBox width
          // reaches the grid.
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 600,
              child: const AutoGrid(
                children: [SizedBox(), SizedBox(), SizedBox(), SizedBox()],
              ),
            ),
          ),
        ),
      );
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      return delegate.crossAxisCount;
    }

    expect(await columnsAt(500), 2); // phone-width keeps the 2-column layout
    expect(await columnsAt(1000), 4);
    expect(await columnsAt(2000), 8);
  });
}
