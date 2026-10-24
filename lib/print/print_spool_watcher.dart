import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

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
  /// Windows printer pipeline), so the bytes are searched as both.
  static PrintedInvoice? extract(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final latin = latin1.decode(bytes, allowInvalid: true);
    final utf16 = _utf16le(bytes);
    final invoice =
        _pattern.firstMatch(latin)?.group(0) ??
        _pattern.firstMatch(utf16)?.group(0);
    if (invoice == null) return null;
    String? field(String label) => _field(latin, label) ?? _field(utf16, label);
    return PrintedInvoice(
      invoice: invoice,
      name: field('Name'),
      ageSex: field('Age/Sex'),
      refer: field('Refer'),
      date: field('Date'),
      totalAmount: field('Total Amount'),
    );
  }

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
    final printed = PrintInvoiceExtractor.extract(bytes);
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
