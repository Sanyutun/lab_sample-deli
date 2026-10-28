import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/print/print_spool_watcher.dart';

void main() {
  test('extract from emf file', () async {
    final candidates = [
      'test/fixtures/sample.emf',
      'test/fixtures/print.emf',
      'test/fixtures/job.emf',
    ];
    File? target;
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) {
        target = f;
        break;
      }
    }
    if (target == null) {
      markTestSkipped('Put your EMF file at test/fixtures/sample.emf');
      return;
    }
    final bytes = await target.readAsBytes();
    final printed = await PrintInvoiceExtractor.extractAsync(bytes);
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
