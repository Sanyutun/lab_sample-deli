import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/print/print_spool_watcher.dart';

/// Runs the extractor over a real spool file copied out of
/// `C:\Windows\System32\spool\PRINTERS` (see README for how to copy one).
///
/// Set `TWOK_REAL_SPOOL_FILE` to the copy and run:
///   flutter test test/real_spool_file_test.dart
void main() {
  test('a real POS-80 spool file is parsed', () async {
    final path = Platform.environment['TWOK_REAL_SPOOL_FILE'];
    if (path == null || path.trim().isEmpty || !File(path).existsSync()) {
      markTestSkipped('set TWOK_REAL_SPOOL_FILE to a copied .SPL file');
      return;
    }
    final printed = PrintInvoiceExtractor.extract(
      await File(path).readAsBytes(),
    );
    expect(printed, isNotNull, reason: 'nothing detected in the real job');
    // ignore: avoid_print
    print(
      'invoice=${printed!.invoice}\n'
      'name=${printed.name}\n'
      'ageSex=${printed.ageSex}\n'
      'refer=${printed.refer}\n'
      'date=${printed.date}\n'
      'totalAmount=${printed.totalAmount}',
    );
  });
}
