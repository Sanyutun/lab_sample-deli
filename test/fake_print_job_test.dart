import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/print/print_spool_watcher.dart';

/// Checks the file `tool/fake_print_job.ps1` writes is what the real extractor
/// reads, so the manual test recipe cannot drift from the parser.
void main() {
  test('the fake print job script produces a readable spool file', () async {
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}twok_spool_test',
    );
    if (!dir.existsSync()) {
      markTestSkipped('run tool/fake_print_job.ps1 first');
      return;
    }
    final spl = dir
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.toLowerCase().endsWith('.spl'));

    final printed = PrintInvoiceExtractor.extract(await spl.readAsBytes());
    expect(printed, isNotNull, reason: 'the job was not detected at all');
    expect(printed!.invoice, '001KHL0001234');
    expect(printed.name, 'Aye Chan');
    expect(printed.ageSex, '34/F');
    expect(printed.refer, 'Dr. Lin');
    expect(printed.totalAmount, '75,000 MMK');
    expect(printed.date, isNotNull);
  });
}
