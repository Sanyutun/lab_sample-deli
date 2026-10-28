import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/print/print_spool_watcher.dart';

void main() {
  test('extract from emf file', () async {
    final path = 'test/fixtures/sample.emf';
    final file = File(path);
    if (!file.existsSync()) {
      // try other common names
      final alt = File('test/fixtures/print.emf');
      if (!alt.existsSync()) {
        markTestSkipped('Put your EMF file at $path or test/fixtures/print.emf');
        return;
      }
    }
    final bytes = await File(file.existsSync() ? path : 'test/fixtures/print.emf').readAsBytes();
    final printed = PrintInvoiceExtractor.extract(bytes);
    expect(printed, isNotNull, reason: 'No invoice extracted from EMF');
    // ignore: avoid_print
    print('invoice=${printed!.invoice}');
    print('name=${printed.name}');
    print('ageSex=${printed.ageSex}');
    print('refer=${printed.refer}');
    print('date=${printed.date}');
    print('totalAmount=${printed.totalAmount}');
  });
}
