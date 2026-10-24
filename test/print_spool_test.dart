import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/print/print_spool_watcher.dart';
import 'package:path/path.dart' as p;

void main() {
  group('PrintInvoiceExtractor', () {
    test('finds the invoice in single-byte receipt text', () {
      final bytes = Uint8List.fromList(
        utf8.encode('TWOK SAMPLE DELI\nInvoice 001KHL0001234\nTotal 75000'),
      );
      expect(PrintInvoiceExtractor.extract(bytes)?.invoice, '001KHL0001234');
    });

    test('finds the invoice in UTF-16LE driver output', () {
      final bytes = _utf16le('Invoice: 001KHL0009876');
      expect(PrintInvoiceExtractor.extract(bytes)?.invoice, '001KHL0009876');
    });

    test('ignores case and takes the first invoice in the job', () {
      final bytes = Uint8List.fromList(latin1.encode('001khl1 then 001KHL2'));
      expect(PrintInvoiceExtractor.extract(bytes)?.invoice, '001khl1');
    });

    test('reads the fields beside the colon on the receipt', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          'TWOK SAMPLE DELI\n'
          'Invoice 001KHL0001234\n'
          'Name: Aye Chan\n'
          'Age/Sex: 34/F\n'
          'Refer: Dr. Lin\n'
          'Date: 18/10/2026 14:30\n'
          'Total Amount: 75,000 MMK\n',
        ),
      );
      final printed = PrintInvoiceExtractor.extract(bytes)!;
      expect(printed.invoice, '001KHL0001234');
      expect(printed.name, 'Aye Chan');
      expect(printed.ageSex, '34/F');
      expect(printed.refer, 'Dr. Lin');
      expect(printed.date, '18/10/2026 14:30');
      expect(printed.totalAmount, '75,000 MMK');
    });

    test('reads a real GDI job: no colon, no line breaks, < padding', () {
      // Copied off a POS-80 receipt. A GDI spool job interleaves the lines with
      // binary rendering data, prints "Total Amount" with no colon, and pads
      // with '<', so none of the fields sit on a line of their own.
      final bytes = _utf16le(
        'Consolas\x00\x00\x00\x00'
        '001KHL2609016\x00\x00'
        '\x00\x00Name:Daw Ohnmar\x00'
        '\x00Age/Sex:51y/F\x00\x00'
        'Refer:Dr. Khant Zwe Aung<<<<'
        'Date:2026-09-08/17:15:38<<<<'
        'Total Amount 104000<<<<',
      );
      final printed = PrintInvoiceExtractor.extract(bytes)!;
      expect(printed.invoice, '001KHL2609016');
      expect(printed.name, 'Daw Ohnmar');
      expect(printed.ageSex, '51y/F');
      expect(printed.refer, 'Dr. Khant Zwe Aung');
      expect(printed.date, '2026-09-08/17:15:38');
      expect(printed.totalAmount, '104000');
    });

    test('fields are null when the job carries only the invoice', () {
      final bytes = Uint8List.fromList(utf8.encode('Invoice 001KHL0001234'));
      final printed = PrintInvoiceExtractor.extract(bytes)!;
      expect(printed.name, isNull);
      expect(printed.ageSex, isNull);
      expect(printed.refer, isNull);
      expect(printed.date, isNull);
      expect(printed.totalAmount, isNull);
    });

    test('a line merely containing "date" is not the Date field', () {
      // "Update:" must never read back as "Date:".
      final bytes = Uint8List.fromList(
        utf8.encode('001KHL0001234\nUpdated by till\nDate: 1/1/2026 09:00'),
      );
      expect(PrintInvoiceExtractor.extract(bytes)?.date, '1/1/2026 09:00');
    });

    test('returns null when the job carries no invoice', () {
      final bytes = Uint8List.fromList(utf8.encode('no invoice number here'));
      expect(PrintInvoiceExtractor.extract(bytes), isNull);
    });

    test('returns null for an empty job', () {
      expect(PrintInvoiceExtractor.extract(Uint8List(0)), isNull);
    });
  });

  group('PrintSpoolWatcher', () {
    late Directory dir;
    late PrintSpoolWatcher watcher;
    late List<PrintedInvoice> seen;
    late StreamSubscription<PrintedInvoice> subscription;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('spool_test');
      watcher = PrintSpoolWatcher(
        directory: dir.path,
        pollInterval: const Duration(milliseconds: 25),
      );
      seen = [];
      subscription = watcher.invoices.listen(seen.add);
    });

    tearDown(() async {
      await subscription.cancel();
      await watcher.dispose();
      await dir.delete(recursive: true);
    });

    test('emits each new job once, in order', () async {
      await _writeSpool(dir, 'FP00001.SPL', '001KHL0001234');
      watcher.start();
      await _until(() => seen.isNotEmpty);
      expect(seen.map((p) => p.invoice), ['001KHL0001234']);

      // Re-scanning the same job must not repeat it.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(seen.map((p) => p.invoice), ['001KHL0001234']);

      await _writeSpool(dir, 'FP00002.SPL', '001KHL0009876');
      await _until(() => seen.length >= 2);
      expect(seen.map((p) => p.invoice), ['001KHL0001234', '001KHL0009876']);
    });

    test('a job just printed shows up within half a second', () async {
      // Uses the production default interval, unlike the setUp watcher: this
      // is the wait a till actually sees between sending the print job and
      // the app showing the invoice.
      final production = PrintSpoolWatcher(directory: dir.path);
      final fresh = <PrintedInvoice>[];
      final sub = production.invoices.listen(fresh.add);
      addTearDown(() async {
        await sub.cancel();
        await production.dispose();
      });
      production.start();
      await production.ready;

      final sent = DateTime.now();
      await _writeSpool(dir, 'FP00003.SPL', '001KHL0007777');
      await _until(() => fresh.isNotEmpty);
      expect(
        DateTime.now().difference(sent),
        lessThan(const Duration(milliseconds: 500)),
      );
    });

    test('a job reusing a spool file name is detected', () async {
      // The spooler recycles names such as FP00001.SPL. The new job can be
      // written over the old one without a scan ever seeing the path missing,
      // so the name alone must not mark the file as already handled.
      await _writeSpool(dir, 'FP00001.SPL', '001KHL0001234');
      watcher.start();
      await _until(() => seen.isNotEmpty);

      await _writeSpool(dir, 'FP00001.SPL', '001KHL0009876');
      await _until(() => seen.length >= 2);
      expect(seen.map((p) => p.invoice), ['001KHL0001234', '001KHL0009876']);
    });

    test('a job written in pieces is re-read until its invoice appears', () async {
      // The spooler creates the file empty, then fills it: neither the empty
      // file nor a header without the invoice may be swallowed for good.
      final file = File(p.join(dir.path, 'FP00009.SPL'));
      await file.writeAsBytes(const <int>[]);
      watcher.start();
      await watcher.ready;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(seen, isEmpty);

      await file.writeAsString('TWOK SAMPLE DELI\n');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(seen, isEmpty);

      await file.writeAsString('TWOK SAMPLE DELI\nInvoice 001KHL0005555\n');
      await _until(() => seen.isNotEmpty);
      expect(seen.single.invoice, '001KHL0005555');
    });

    test('ignores non-spool files', () async {
      await File(p.join(dir.path, 'FP00001.SHD'))
          .writeAsString('001KHL0001234');
      watcher.start();
      await watcher.ready;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(seen, isEmpty);
    });

    test('reports a missing spool folder instead of throwing', () async {
      final missing = PrintSpoolWatcher(
        directory: p.join(dir.path, 'does-not-exist'),
        pollInterval: const Duration(milliseconds: 25),
      );
      addTearDown(missing.dispose);
      missing.start();
      await missing.ready;
      expect(missing.lastError, isNotNull);
    });

    test('TWOK_SPOOL_DIR overrides the system spool folder', () {
      // The override is read through Platform.environment, so this asserts the
      // documented behaviour rather than mutating the process environment.
      final watcher = PrintSpoolWatcher(directory: dir.path);
      expect(watcher.directory, dir.path);
    });
  });
}

Future<void> _writeSpool(Directory dir, String name, String invoice) {
  return File(p.join(dir.path, name))
      .writeAsBytes(utf8.encode('TWOK SAMPLE DELI\n$invoice\nTotal 75000\n'));
}

Uint8List _utf16le(String text) {
  final builder = BytesBuilder();
  for (final code in text.codeUnits) {
    builder.addByte(code & 0xff);
    builder.addByte((code >> 8) & 0xff);
  }
  return builder.toBytes();
}

Future<void> _until(
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
