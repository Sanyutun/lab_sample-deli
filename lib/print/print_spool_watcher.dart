import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'emf_image_decoder.dart';

/// One printed receipt: its invoice number plus the labelled fields the shop
/// reads off it. A field is null when the job's text carried no such line.
class PrintedInvoice {
  const PrintedInvoice({
    required this.invoice,
    this.name,
    this.ageSex,
    this.refer,
    this.date,
    this.totalAmount,
  });

  /// Invoice number, e.g. `001KHL0001234`.
  final String invoice;

  final String? name;
  final String? ageSex;
  final String? refer;
  final String? date;
  final String? totalAmount;
}

/// Pulls the invoice number and the labelled fields out of a raw Windows
/// print job.
///
/// This shop's invoices always start with [prefix] followed by the serial
/// digits, e.g. `001KHL0001234`. Change [prefix] here if the format ever
/// changes.
class PrintInvoiceExtractor {
  PrintInvoiceExtractor._();

  static const String prefix = '001KHL';

  static final RegExp _pattern = RegExp(
    '${RegExp.escape(prefix)}[0-9]+',
    caseSensitive: false,
  );

  /// The invoice and fields in [bytes], or null when the job holds no invoice.
  ///
  /// Spool data is either single-byte (ESC/POS receipt text) or UTF-16LE (the
  /// Windows printer pipeline), so the bytes are searched as both. EMF/GDI
  /// spool jobs often bury the text in EMF records or draw it directly; we
  /// also scan extracted EMF text and the raw bytes as a last resort.
  static PrintedInvoice? extract(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final latin = latin1.decode(bytes, allowInvalid: true);
    final utf16 = _utf16le(bytes);
    final emfText = _extractEmfText(bytes);
    // Also try scanning as UTF-16BE just in case
    final utf16be = _utf16be(bytes);
    String? invoice =
        _pattern.firstMatch(latin)?.group(0) ??
        _pattern.firstMatch(utf16)?.group(0) ??
        _pattern.firstMatch(utf16be)?.group(0) ??
        _pattern.firstMatch(emfText)?.group(0);
    if (invoice == null) {
      invoice = _findCode128Like(bytes);
    }
    if (invoice == null) {
      invoice = _aggressiveScan(bytes);
    }
    // If still null and it's EMF data, try image-based decoding (Windows only) - async but we need to handle
    if (invoice == null && Platform.isWindows) {
      if (bytes.length > 4 && bytes[0] == 0x01 && bytes[1] == 0x00 && bytes[2] == 0x00 && bytes[3] == 0x00) {
        // Try to decode synchronously by running in microtask isn't possible here
        // But we can store for async processing - for now mark for later
      }
    }
    if (invoice == null) return null;
    String? field(String label) =>
        _field(latin, label) ??
        _field(utf16, label) ??
        _field(utf16be, label) ??
        _field(emfText, label);
    return PrintedInvoice(
      invoice: invoice,
      name: field('Name'),
      ageSex: field('Age/Sex'),
      refer: field('Refer'),
      date: field('Date'),
      totalAmount: field('Total Amount'),
    );
  }

  /// Async version that can decode barcodes from EMF graphics
  static Future<PrintedInvoice?> extractAsync(Uint8List bytes) async {
    final syncResult = extract(bytes);
    if (syncResult != null) return syncResult;
    if (!Platform.isWindows) return null;
    if (bytes.length > 4 && bytes[0] == 0x01 && bytes[1] == 0x00 && bytes[2] == 0x00 && bytes[3] == 0x00) {
      try {
        final decoded = await EmfImageDecoder.decodeBarcode(bytes);
        if (decoded != null && decoded.isNotEmpty) {
          final m = _pattern.firstMatch(decoded) ?? _pattern.firstMatch(decoded.toUpperCase());
          final invoice = m?.group(0) ?? decoded.trim();
          if (invoice.isNotEmpty) {
            return PrintedInvoice(invoice: invoice);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static String? _aggressiveScan(Uint8List bytes) {
    // Try to find by sliding window over all byte permutations
    final target = prefix.toLowerCase();
    // Search in latin1
    final latin = latin1.decode(bytes, allowInvalid: true).toLowerCase();
    var idx = latin.indexOf(target);
    if (idx >= 0) {
      final sb = StringBuffer();
      for (var i = idx; i < latin.length && sb.length < 12; i++) {
        final c = latin.codeUnitAt(i);
        if ((c >= 97 && c <= 122) || (c >= 48 && c <= 57)) {
          sb.write(String.fromCharCode(c >= 97 && c <= 122 ? c - 32 : c));
        } else {
          break;
        }
      }
      final res = sb.toString();
      if (res.toLowerCase().startsWith(target)) return res;
    }
    // Search UTF-16LE chars
    for (var i = 0; i < bytes.length - 20; i += 1) {
      // Try to reconstruct if every other byte is 0
      if (bytes[i + 1] == 0 || i + 10 < bytes.length && bytes[i + 3] == 0) {
        final sb = StringBuffer();
        var j = i;
        while (j + 1 < bytes.length && sb.length < 12) {
          final c = bytes[j];
          if (bytes[j + 1] == 0) {
            if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57)) {
              sb.writeCharCode(c >= 97 && c <= 122 ? c - 32 : c);
              j += 2;
              continue;
            } else if (c == 0) {
              break;
            } else {
              break;
            }
          } else {
            break;
          }
        }
        final res = sb.toString();
        if (res.length >= 6 && res.toLowerCase().startsWith(target)) return res;
      }
    }
    return null;
  }

  /// Try to find a Code 128 barcode string (our invoice format) by scanning
  /// for the prefix pattern in raw byte streams where text may be packed
  /// differently.
  static String? _findCode128Like(dynamic source) {
    if (source == null) return null;
    if (source is String) {
      final m = _pattern.firstMatch(source);
      if (m != null) return m.group(0);
      // Also try to find by scanning for prefix chars
      return _scanForPrefix(source);
    }
    if (source is Uint8List) {
      // Try multiple encodings
      final encodings = [
        latin1.decode(source, allowInvalid: true),
        _utf16le(source),
        _utf16be(source),
      ];
      for (final t in encodings) {
        final m = _pattern.firstMatch(t);
        if (m != null) return m.group(0);
        final s = _scanForPrefix(t);
        if (s != null) return s;
      }
      // Raw byte scan for ASCII pattern
      return _scanRawBytes(source);
    }
    if (source is List<int>) {
      return _findCode128Like(Uint8List.fromList(source));
    }
    return null;
  }

  static String? _scanForPrefix(String text) {
    final lower = text.toLowerCase();
    final p = prefix.toLowerCase();
    final idx = lower.indexOf(p);
    if (idx < 0) return null;
    // Extract following digits
    final buf = StringBuffer();
    for (var i = idx; i < text.length && buf.length < 20; i++) {
      final c = text[i];
      if ((c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
          (c.toLowerCase() == p[buf.length]) ||
          (buf.isEmpty && c.toLowerCase() == p[0]) && buf.length == 0) {
        // Better to just take contiguous prefix+digits
      }
    }
    // Simpler: take from idx while alphanumeric
    final sb = StringBuffer();
    for (var i = idx; i < text.length && i < idx + 15; i++) {
      final c = text.codeUnitAt(i);
      if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57)) {
        sb.write(String.fromCharCode(c));
      } else {
        break;
      }
    }
    final result = sb.toString();
    if (result.length >= 6 && result.toLowerCase().startsWith(p)) {
      return result;
    }
    return null;
  }

  static String? _scanRawBytes(Uint8List bytes) {
    final p = prefix.codeUnits;
    for (var i = 0; i < bytes.length - p.length - 5; i++) {
      var match = true;
      for (var j = 0; j < p.length; j++) {
        if (bytes[i + j] != p[j] && bytes[i + j] != (p[j] >= 97 ? p[j] - 32 : p[j] + 32)) {
          match = false;
          break;
        }
      }
      if (match) {
        final sb = StringBuffer();
        for (var k = i; k < bytes.length && sb.length < 15; k++) {
          final b = bytes[k];
          if ((b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57)) {
            sb.writeCharCode(b);
          } else {
            break;
          }
        }
        final res = sb.toString();
        if (res.toLowerCase().startsWith(prefix.toLowerCase())) return res;
      }
    }
    return null;
  }

  /// Extracts printable text from Enhanced Metafile (EMF) records.
  /// Looks for EMR_EXTTEXTOUT (0x52), EMR_POLYTEXTOUT (0x60),
  /// EMR_EXTTEXTOUTW (0x54) style records and pulls string data.
  static String _extractEmfText(Uint8List bytes) {
    if (bytes.length < 88) return '';
    // EMF signature
    if (!(bytes[0] == 0x01 && bytes[1] == 0x00 && bytes[2] == 0x00 && bytes[3] == 0x00)) {
      // Some spool files may not start at EMF header; still try to scan
    }
    final buffer = StringBuffer();
    var offset = 0;
    final len = bytes.length;
    while (offset + 8 <= len) {
      final type = _u32(bytes, offset);
      final size = _u32(bytes, offset + 4);
      if (size < 8 || offset + size > len) break;
      // EMR_EXTTEXTOUT = 0x52, EMR_POLYTEXTOUT = 0x60, EMR_EXTTEXTOUTA = 0x53, EMR_EXTTEXTOUTW = 0x54
      if (type == 0x52 || type == 0x53 || type == 0x54 || type == 0x60) {
        _extractTextFromEmrRecord(bytes, offset, size, buffer);
      }
      offset += size;
      // align to 4 bytes if needed (records are DWORD aligned)
      if (offset % 4 != 0) offset += (4 - (offset % 4));
    }
    return buffer.toString();
  }

  static void _extractTextFromEmrRecord(
    Uint8List bytes,
    int recordStart,
    int recordSize,
    StringBuffer buffer,
  ) {
    try {
      // Try to find string data - different record types have different layouts
      // For EMR_EXTTEXTOUTW (0x54), string is often UTF-16LE at offset
      // Scan for plausible string regions
      var i = recordStart + 8;
      final end = recordStart + recordSize;
      while (i + 4 <= end) {
        // Look for UTF-16LE strings with our prefix pattern nearby
        // Check if we see '0','0','1','K','H','L' as UTF-16LE
        if (i + 10 <= end) {
          // Try to read as UTF-16LE starting at i
          final s = _tryReadUtf16At(bytes, i, end);
          if (s != null && s.length >= 6) {
            if (_pattern.hasMatch(s) || s.toLowerCase().contains(prefix.toLowerCase())) {
              buffer.write(s);
              buffer.write(' ');
            } else if (_looksLikeReceiptField(s)) {
              buffer.write(s);
              buffer.write('\n');
            }
          }
        }
        i += 2;
      }
    } catch (_) {}
  }

  static String? _tryReadUtf16At(Uint8List bytes, int start, int end) {
    // Read up to reasonable length
    final maxLen = 200;
    var count = 0;
    var j = start;
    while (j + 1 < end && count < maxLen) {
      final c = bytes[j] | (bytes[j + 1] << 8);
      if (c == 0) break; // null terminator
      if (c < 32 && c != 9 && c != 10 && c != 13) {
        // Check if it's a printable char in extended range
        if (c > 126) break;
      }
      count++;
      j += 2;
    }
    if (count < 3) return null;
    final chars = <int>[];
    for (var k = 0; k < count; k++) {
      chars.add(bytes[start + k * 2] | (bytes[start + k * 2 + 1] << 8));
    }
    try {
      return String.fromCharCodes(chars);
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeReceiptField(String s) {
    final l = s.toLowerCase();
    return l.contains('name') ||
        l.contains('age') ||
        l.contains('sex') ||
        l.contains('refer') ||
        l.contains('date') ||
        l.contains('total') ||
        l.contains('amount') ||
        l.contains('invoice');
  }

  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  /// The text after `label`, trimmed; null when absent.
  ///
  /// A GDI spool job interleaves the receipt lines with binary rendering data,
  /// so the label is *not* on a line of its own: it is matched at a word
  /// boundary instead. The `\b` keeps "Update:" from reading back as "Date:",
  /// and the colon is optional because real receipts print "Total Amount 104000"
  /// without one. The value stops at a control character, at `<` (this printer
  /// pads with it), or after [maxValueLength] characters.
  static String? _field(String text, String label) => RegExp(
    '\\b${RegExp.escape(label)}\\b:?[ \\t]*([^\\x00-\\x1F<>]{1,$maxValueLength})',
    caseSensitive: false,
  ).firstMatch(text)?.group(1)?.trim();

  /// Longest value a field may hold. Guards against a missing label matching a
  /// whole slab of binary data.
  static const int maxValueLength = 60;

  static String _utf16le(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      buffer.writeCharCode(bytes[i] | (bytes[i + 1] << 8));
    }
    return buffer.toString();
  }

  static String _utf16be(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      buffer.writeCharCode((bytes[i] << 8) | bytes[i + 1]);
    }
    return buffer.toString();
  }
}

/// Watches the Windows print-spool folder and emits the invoice number of each
/// new print job.
///
/// The spooler writes one `.SPL` file per job and deletes it once the job is
/// despooled, so the folder is watched for changes, with a poll as the
/// fallback for a change event the app was too busy to receive. Reading
/// `%SystemRoot%\System32\spool\PRINTERS` needs permission; when it is not
/// readable [lastError] says so and nothing is emitted. The office app must run
/// with rights to read that folder (see the Print Monitor screen).
class PrintSpoolWatcher {
  PrintSpoolWatcher({
    String? directory,
    // The fallback scan. A change in the folder is handled as soon as the
    // watcher reports it, so this only covers a missed change event.
    this.pollInterval = const Duration(milliseconds: 200),
  }) : directory = directory ?? defaultDirectory;

  /// `%SystemRoot%\System32\spool\PRINTERS`, unless `TWOK_SPOOL_DIR` points
  /// somewhere else. The override lets a test (or a shop whose printer writes
  /// elsewhere) feed the watcher a folder of its own.
  static String get defaultDirectory {
    final override = Platform.environment['TWOK_SPOOL_DIR'];
    if (override != null && override.trim().isNotEmpty) return override.trim();
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return p.join(root, 'System32', 'spool', 'PRINTERS');
  }

  final String directory;
  final Duration pollInterval;

  final StreamController<PrintedInvoice> _controller =
      StreamController<PrintedInvoice>.broadcast();

  /// What was last read from each spool file, by path. The spooler reuses
  /// file names, so the path alone does not identify a job: [_SpoolJob.invoice]
  /// does.
  final Map<String, _SpoolJob> _jobs = {};

  Timer? _timer;
  StreamSubscription<FileSystemEvent>? _folderWatch;
  Future<void>? _firstScan;
  bool _scanning = false;
  String? _lastError;

  /// Printed receipts found in new jobs, in the order they were spooled.
  Stream<PrintedInvoice> get invoices => _controller.stream;

  bool get isRunning => _timer != null;
  String? get lastError => _lastError;

  /// Completes after the first scan of the latest [start], so a caller can read
  /// [lastError] once the folder has actually been looked at.
  Future<void> get ready => _firstScan ?? Future<void>.value();

  void start() {
    if (_timer != null) return;
    _firstScan = _scan();
    _timer = Timer.periodic(pollInterval, (_) => _scan());
    _watchFolder();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _folderWatch?.cancel();
    _folderWatch = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  /// Scans as soon as the folder changes, so a short-lived job is caught even
  /// when the fallback poll is late. Dart's Windows watch is OS-driven
  /// (ReadDirectoryChangesW); a dropped watch falls back to the poll.
  void _watchFolder() {
    if (_folderWatch != null || !isRunning) return;
    _folderWatch = Directory(directory).watch().listen(
      (_) => _scan(),
      onError: (Object _) => _folderWatch = null,
      onDone: () => _folderWatch = null,
    );
  }

  Future<void> _scan() async {
    // One scan at a time: a folder change can fire while a poll is still
    // reading, and two scans would emit the same job twice.
    if (_scanning) return;
    _scanning = true;
    try {
      await _scanOnce();
    } finally {
      _scanning = false;
    }
  }

  Future<void> _scanOnce() async {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      _lastError = 'Spool folder not found: $directory';
      return;
    }
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } on FileSystemException catch (e) {
      _lastError =
          'Cannot read the spool folder (${e.osError?.message ?? e.message}). '
          'Run the app with rights to read it.';
      return;
    }
    _lastError = null;
    // The folder may have appeared after start() (or a watch may have failed).
    _watchFolder();

    final splFiles = <File>[
      for (final entity in entries)
        if (entity is File && entity.path.toLowerCase().endsWith('.spl'))
          entity,
    ];
    // Forget jobs the spooler has finished and deleted, so a reused file name
    // is treated as a fresh job.
    final present = {for (final f in splFiles) f.path};
    _jobs.removeWhere((path, _) => !present.contains(path));

    for (final file in splFiles) {
      await _scanFile(file);
    }
  }

  Future<void> _scanFile(File file) async {
    final FileStat stat;
    try {
      stat = await file.stat();
    } on FileSystemException {
      _jobs.remove(file.path);
      return; // already despooled and deleted
    }
    final job = _jobs[file.path];
    // Nothing changed since the last read of this file.
    if (job != null && job.size == stat.size && job.modified == stat.modified) {
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return; // locked or gone; retry on the next scan
    }
    var printed = PrintInvoiceExtractor.extract(bytes);
    if (printed == null && Platform.isWindows) {
      // Try async EMF image decode
      printed = await PrintInvoiceExtractor.extractAsync(bytes);
    }
    // The invoice already emitted under this path means the spooler is still
    // writing the same job. A different invoice means the spooler recycled the
    // file name for a new job — emit it.
    // shortcut: reprinting the same invoice before the path is seen missing is
    // treated as the same job and not shown again; upgrade to file IDs if that
    // ever matters.
    if (printed == null || printed.invoice == job?.invoice) {
      _jobs[file.path] = _SpoolJob(stat.size, stat.modified, job?.invoice);
      return;
    }
    _jobs[file.path] = _SpoolJob(stat.size, stat.modified, printed.invoice);
    if (!_controller.isClosed) _controller.add(printed);
  }
}

/// The last read of one spool file.
class _SpoolJob {
  const _SpoolJob(this.size, this.modified, this.invoice);

  final int size;
  final DateTime modified;

  /// The invoice already emitted for this file, or null while it has none.
  final String? invoice;
}

/// The office app's one spool watcher.
///
/// The app listens to it wherever the user is and opens the delivery flow for
/// every invoice; the Print Monitor screen only shows its state and can stop
/// and start it, so detection keeps working after leaving that screen.
final PrintSpoolWatcher officeSpoolWatcher = PrintSpoolWatcher();
