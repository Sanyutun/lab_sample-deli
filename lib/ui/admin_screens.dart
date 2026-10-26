// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/dashboard_features.dart';
import '../domain/exceptions.dart';
import '../domain/services/reconciliation_service.dart';
import 'common.dart';

import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Official receipt import
// ---------------------------------------------------------------------------
class OfficialReceiptImportScreen extends StatefulWidget {
  const OfficialReceiptImportScreen({super.key});

  @override
  State<OfficialReceiptImportScreen> createState() =>
      _OfficialReceiptImportScreenState();
}

class _OfficialReceiptImportScreenState
    extends State<OfficialReceiptImportScreen> {
  bool _busy = false;
  String _status = '';
  int _officialCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = AppScope.of(context);
    final count = await s.reconciliation.officialCount();
    if (mounted) setState(() => _officialCount = count);
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
    );
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final s = AppScope.of(context);
    var imported = 0;
    var filesDone = 0;
    final dupes = <String>{};
    final errors = <String>[];
    try {
      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          final rows = _isCsv(file.name)
              ? _parseCsv(bytes)
              : _parseExcel(bytes);
          final parsed = OfficialReceiptParser.parse(file.name, rows);
          final report = await s.reconciliation.importOfficialReceipts(parsed);
          imported += report.imported;
          filesDone++;
          dupes.addAll(report.duplicateBarcodes);
        } on AppException catch (e) {
          errors.add('${file.name}: ${e.message}');
        } on Exception catch (e) {
          errors.add('${file.name}: $e');
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    setState(() {
      _status =
          'Imported $imported official receipts from $filesDone file(s).'
          '${dupes.isEmpty ? '' : ' ${dupes.length} barcode(s) were already imported earlier and were skipped: ${dupes.take(20).join(', ')}${dupes.length > 20 ? ' …' : ''}'}'
          '${errors.isEmpty ? '' : ' ${errors.length} file(s) failed: ${errors.take(5).join('; ')}${errors.length > 5 ? ' …' : ''}'}';
    });
    showMessage(
      context,
      errors.isEmpty
          ? 'Imported $imported receipts'
          : 'Imported $imported receipts, ${errors.length} file(s) failed',
      error: errors.isNotEmpty,
    );
    _refresh();
  }

  bool _isCsv(String name) => name.toLowerCase().endsWith('.csv');

  List<List<dynamic>> _parseCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.contains('\uFFFD')) {
      try {
        text = latin1.decode(bytes);
      } catch (_) {}
    }
    return Csv(dynamicTyping: false).decode(text);
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final excel = _decodeExcel(bytes);
    if (excel.tables.isEmpty) {
      throw const AppException('This Excel file does not contain any sheets.');
    }
    final sheet = excel.tables[excel.tables.keys.first]!;
    return sheet.rows
        .map((row) => row.map((cell) => cell?.value ?? '').toList())
        .toList();
  }

  Excel _decodeExcel(Uint8List bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } catch (_) {
      // Some lab exports omit xl/sharedStrings.xml. The excel package then
      // matches the zero-length "xl/" directory entry as the shared-strings
      // part and fails with "Expected a single root element". Re-encoding the
      // workbook without directory entries avoids that code path.
      try {
        return Excel.decodeBytes(_stripZipDirectories(bytes));
      } catch (_) {
        throw const AppException(
          'Could not read this Excel file. Open it in Excel and re-save it as '
          'CSV or as a new .xlsx workbook, then import it again.',
        );
      }
    }
  }

  Uint8List _stripZipDirectories(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = Archive();
    for (final file in archive) {
      if (!file.isFile || file.name.endsWith('/')) continue;
      out.addFile(file);
    }
    return Uint8List.fromList(ZipEncoder().encode(out)!);
  }

  Future<void> _clearAll() async {
    final ok = await confirmDialog(
      context,
      'Clear official receipts and reconciliation?',
      'This removes ALL imported official receipts, plus every reconciliation '
          'run and result built from them. Staff commission records are untouched.',
      actionLabel: 'CLEAR',
    );
    if (!ok) return;
    final s = AppScope.of(context);
    await s.receipts.clearOfficial();
    await s.receipts.clearReconciliation();
    await s.audit.record('OFFICIAL_RECEIPTS_CLEARED');
    if (!mounted) return;
    showMessage(context, 'Official receipts and reconciliation cleared');
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Official Receipt Import',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Import the existing receipt-software export (CSV or Excel).\n'
                'You can select several files at once. '
                'Column names sit on the 3rd row and are mapped automatically:\n'
                'Invoice (invoice no) = barcode, Date (+ Time), Refer / Refer by, Patient / Patient name, Net amt = amount.\n'
                'Use a report that also has a Time column — without it the Time Gap cannot be calculated.\n'
                'This is the authoritative source for verifying staff commission records.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: const Text('Official receipts stored'),
                    trailing: Text(
                      '$_officialCount',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.upload_file),
                label: Text(_busy ? 'Importing…' : 'IMPORT CSV / EXCEL FILES'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _clearAll,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear official receipts'),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reconciliation
// ---------------------------------------------------------------------------
class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  static const int _pageSize = 200;

  ReconciliationRun? _run;
  List<ReconciliationResult> _results = [];
  bool _loading = true;
  bool _running = false;
  int _visible = _pageSize;
  double _gapHours = SettingsRepository.defaultReconTimeGapHours;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = AppScope.of(context);
    final (run, results) = await s.reconciliation.latest();
    final gap = await s.settings.get(SettingsRepository.reconTimeGapHoursKey);
    if (!mounted) return;
    setState(() {
      _run = run;
      _results = results;
      _visible = _pageSize;
      _loading = false;
      _gapHours =
          double.tryParse(gap?.trim() ?? '') ??
          SettingsRepository.defaultReconTimeGapHours;
    });
  }

  Future<void> _execute() async {
    final s = AppScope.of(context);
    setState(() => _running = true);
    try {
      final run = await s.reconciliation.run(
        createdBy: s.auth.requireUser().id,
      );
      final results = await s.receipts.resultsForRun(run.id);
      if (!mounted) return;
      setState(() {
        _run = run;
        _results = results;
        _visible = _pageSize;
      });
      showMessage(context, 'Reconciliation complete');
    } on AppException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// Receipt exports are 'yyyy-MM-dd HH:mm' when the file carried a Time
  /// column, 'yyyy-MM-dd' otherwise; render both as dd/MM/yyyy.
  String _fmtReceipt(String? raw) {
    if (raw == null || raw.isEmpty) return '--';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return DateFormat(raw.contains(' ') ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy')
        .format(d);
  }

  Widget _gapCell(ReconciliationResult r) {
    final gap = r.timeGap;
    if (gap == null) return const Text('--');
    final text = '${gap.inHours}h ${gap.inMinutes % 60}m';
    return gap.inMinutes > _gapHours * 60
        ? statusChip('OVER $text')
        : Text(text);
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    // Detailed results list only barcodes that were actually scanned; unclaimed
    // official receipts (never scanned) stay in the summary counts above.
    final scanned = _results
        .where((r) => r.status != ReconciliationStatus.unclaimed)
        .toList();
    final visibleResults = scanned.length > _visible
        ? scanned.sublist(0, _visible)
        : scanned;
    return PageScaffold(
      title: 'Reconciliation',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                FilledButton.icon(
                  onPressed: _running ? null : _execute,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_running ? 'Running…' : 'RUN RECONCILIATION'),
                ),
                const SizedBox(height: 12),
                if (run == null)
                  const EmptyState(
                    message: 'No reconciliation run yet.\nOfficial receipts must be imported first.',
                  )
                else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reconciliation summary',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          AutoGrid(
                            childAspectRatio: 2.4,
                            children: [
                              statCard(
                                context,
                                'Official receipts',
                                '${run.officialCount}',
                              ),
                              statCard(
                                context,
                                'Staff records',
                                '${run.staffCount}',
                              ),
                              statCard(
                                context,
                                'MATCH',
                                '${run.matchCount}',
                                color: Colors.green,
                              ),
                              statCard(
                                context,
                                'COMMISSION MISMATCH',
                                '${run.mismatchCount}',
                                color: Colors.orange,
                              ),
                              statCard(
                                context,
                                'NOT FOUND',
                                '${run.notFoundCount}',
                                color: Colors.red,
                              ),
                              statCard(
                                context,
                                'DUPLICATE',
                                '${run.duplicateCount}',
                                color: Colors.purple,
                              ),
                              statCard(
                                context,
                                'UNCLAIMED RECEIPTS',
                                '${run.unclaimedCount}',
                                color: Colors.blueGrey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SectionTitle('Detailed results (${scanned.length})'),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 18,
                      columns: const [
                        DataColumn(label: Text('Barcode')),
                        DataColumn(label: Text('Patient')),
                        DataColumn(label: Text('Receipt Amount')),
                        DataColumn(label: Text('Refer')),
                        DataColumn(label: Text('Delivery Man')),
                        DataColumn(label: Text('Entered')),
                        DataColumn(label: Text('Expected')),
                        DataColumn(label: Text('Receipt Date/Time')),
                        DataColumn(label: Text('Commission Date/Time')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Time Gap')),
                      ],
                      rows: [
                        for (final r in visibleResults)
                          DataRow(
                            cells: [
                              DataCell(Text(r.barcode)),
                              DataCell(
                                Text(r.patient.isEmpty ? '--' : r.patient),
                              ),
                              DataCell(
                                Text(
                                  r.receiptAmount == null
                                      ? '--'
                                      : fmtMMK(r.receiptAmount!),
                                ),
                              ),
                              DataCell(Text(r.refer.isEmpty ? '--' : r.refer)),
                              DataCell(
                                Text(
                                  r.deliveryManName ?? r.deliveryManId ?? '--',
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.enteredCommission == null
                                      ? '--'
                                      : '${r.enteredCommission}',
                                ),
                              ),
                              DataCell(
                                Text(
                                  r.expectedCommission == null
                                      ? '--'
                                      : '${r.expectedCommission}',
                                ),
                              ),
                              DataCell(Text(_fmtReceipt(r.receiptDate))),
                              DataCell(
                                Text(
                                  r.commissionAt == null
                                      ? '--'
                                      : fmtDate(r.commissionAt!),
                                ),
                              ),
                              DataCell(statusChip(r.statusLabel)),
                              DataCell(_gapCell(r)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (scanned.length > _visible)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: OutlinedButton(
                        onPressed: () => setState(() => _visible += _pageSize),
                        child: Text(
                          'Show more (${scanned.length - _visible} remaining)',
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Google Sheets sync
// ---------------------------------------------------------------------------
class SheetsSyncScreen extends StatefulWidget {
  const SheetsSyncScreen({super.key});

  @override
  State<SheetsSyncScreen> createState() => _SheetsSyncScreenState();
}

class _SheetsSyncScreenState extends State<SheetsSyncScreen> {
  bool _busy = false;

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      showMessage(context, message);
    } on AppException catch (e) {
      showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync(String kind) {
    final s = AppScope.of(context);
    return _run(() async {
      if (kind == 'commissions') {
        await s.sheets.syncCommissionRecords();
      } else {
        final (run, results) = await s.reconciliation.latest();
        if (run == null) {
          throw const AppException('Run reconciliation first');
        }
        await s.sheets.syncReconciliation(runId: run.id, results: results);
      }
      return 'Synced to Google Sheets';
    });
  }

  Future<void> _backup() {
    final s = AppScope.of(context);
    return _run(() async {
      final result = await s.sheets.backupAll();
      return 'Backed up ${result.tables} tables, ${result.rows} rows';
    });
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from sheet?'),
        content: const Text(
          'This REPLACES all local data with what is currently in the '
          'Google Sheet backup tabs.\n\nAny records entered since the last '
          'backup will be lost. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RESTORE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final s = AppScope.of(context);
    await _run(() async {
      final result = await s.sheets.restoreAll();
      return 'Restored ${result.tables} tables, ${result.rows} rows';
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = AppScope.of(context).sheets.config;
    return PageScaffold(
      title: 'Google Sheets',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: config.isConfigured
                ? Colors.green.shade50
                : Colors.orange.shade50,
            child: ListTile(
              leading: Icon(
                config.isConfigured ? Icons.check_circle : Icons.info,
                color: config.isConfigured ? Colors.green : Colors.orange,
              ),
              title: Text(
                config.isConfigured
                    ? 'Google Sheets configured'
                    : 'Not configured yet',
              ),
              subtitle: Text(
                config.isConfigured ? 'Spreadsheet ${config.spreadsheetId}' : 'Set spreadsheet ID and service account JSON in Admin Settings.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'BACKUP & RESTORE',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _backup,
            icon: const Icon(Icons.cloud_upload),
            label: const Text('BACKUP ALL DATA TO SHEET'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            icon: const Icon(Icons.cloud_download),
            label: const Text('RESTORE FROM SHEET'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Backup writes one tab per table (including audit logs). '
              'Credentials are never uploaded. Restore rebuilds the local '
              'database from those tabs.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'REPORTING SYNC (append-only)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _sync('commissions'),
            icon: const Icon(Icons.table_chart),
            label: const Text('SYNC COMMISSION RECORDS'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _sync('reconciliation'),
            icon: const Icon(Icons.compare_arrows),
            label: const Text('SYNC RECONCILIATION RESULTS'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin settings
// ---------------------------------------------------------------------------
class AdminSettingsScreen extends StatelessWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Admin Settings',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          _DashboardButtonsSection(),
          Divider(),
          _CommissionRulesSection(),
          Divider(),
          _MilestoneRulesSection(),
          Divider(),
          _UsersSection(),
          Divider(),
          _ReconSettingsSection(),
          Divider(),
          _SheetsConfigSection(),
        ],
      ),
    );
  }
}

class _DashboardButtonsSection extends StatefulWidget {
  const _DashboardButtonsSection();

  @override
  State<_DashboardButtonsSection> createState() =>
      _DashboardButtonsSectionState();
}

class _DashboardButtonsSectionState extends State<_DashboardButtonsSection> {
  Map<String, String> _settings = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await AppScope.of(context).settings.all();
    if (mounted) {
      setState(() {
        _settings = settings;
        _loaded = true;
      });
    }
  }

  bool _on(DashboardFeature feature, {required bool admin}) {
    final value = _settings[feature.visibilityKey(admin: admin)];
    // Buttons that are admin-only start hidden from staff; everything else is
    // visible until an admin turns it off.
    if (value == null) return admin || !feature.adminOnly;
    return value != '0';
  }

  Future<void> _toggle(
    DashboardFeature feature, {
    required bool admin,
    required bool value,
  }) async {
    final key = feature.visibilityKey(admin: admin);
    setState(() => _settings[key] = value ? '1' : '0');
    await AppScope.of(context).settings.set(key, value ? '1' : '0');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final isWindows = Platform.isWindows;
    final features = [
      for (final feature in DashboardFeature.values)
        if (!feature.alwaysVisible &&
            (!feature.windowsOnly || isWindows) &&
            (!feature.androidOnly || !isWindows))
          feature,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Dashboard buttons'),
        Text(
          'Untick a button to hide it from that role. Buttons that are admin '
          'only start unticked for Staff — tick Staff to let them open it. '
          'Admin Settings always stays visible, so you cannot lock yourself out.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text('Button')),
            SizedBox(width: 56, child: Center(child: Text('Staff'))),
            SizedBox(width: 56, child: Center(child: Text('Admin'))),
          ],
        ),
        for (final feature in features)
          Row(
            children: [
              Expanded(child: Text(feature.label)),
              SizedBox(
                width: 56,
                child: Checkbox(
                  value: _on(feature, admin: false),
                  onChanged: (v) =>
                      _toggle(feature, admin: false, value: v ?? false),
                ),
              ),
              SizedBox(
                width: 56,
                child: Checkbox(
                  value: _on(feature, admin: true),
                  onChanged: (v) =>
                      _toggle(feature, admin: true, value: v ?? false),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _CommissionRulesSection extends StatefulWidget {
  const _CommissionRulesSection();

  @override
  State<_CommissionRulesSection> createState() =>
      _CommissionRulesSectionState();
}

class _CommissionRulesSectionState extends State<_CommissionRulesSection> {
  List<CommissionRule> _rules = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await AppScope.of(context).commissions.rules();
    if (mounted) setState(() => _rules = rules);
  }

  Future<void> _add() async {
    final result = await _showForm();
    if (result == null) return;
    final s = AppScope.of(context);
    try {
      final rule = await s.commissions.addRule(
        minAmount: result.min,
        maxAmount: result.max,
        commissionAmount: result.amount,
        active: result.active,
      );
      await s.audit.record(
        'COMMISSION_RULE_ADDED',
        refId: rule.id,
        newValue: _describe(rule),
      );
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _load();
  }

  Future<void> _edit(CommissionRule rule) async {
    final result = await _showForm(rule: rule);
    if (result == null) return;
    final s = AppScope.of(context);
    final updated = CommissionRule(
      id: rule.id,
      minAmount: result.min,
      maxAmount: result.max,
      commissionAmount: result.amount,
      active: result.active,
    );
    try {
      await s.commissions.updateRule(updated);
      await s.audit.record(
        'COMMISSION_RULE_CHANGED',
        refId: rule.id,
        oldValue: _describe(rule),
        newValue: _describe(updated),
      );
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _load();
  }

  /// One dialog for both adding and editing. The error stays inside the dialog
  /// so a typo does not throw the admin's numbers away.
  Future<_RuleForm?> _showForm({CommissionRule? rule}) async {
    final minC = TextEditingController(
      text: rule == null ? '' : '${rule.minAmount}',
    );
    final maxC = TextEditingController(text: rule?.maxAmount?.toString() ?? '');
    final amtC = TextEditingController(
      text: rule == null ? '' : '${rule.commissionAmount}',
    );
    var active = rule?.active ?? true;
    String? error;
    return showDialog<_RuleForm>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(rule == null ? 'New commission rule' : 'Commission rule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minC,
                autofocus: rule == null,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Min receipt total',
                ),
              ),
              TextField(
                controller: maxC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max receipt total (empty = no limit)',
                ),
              ),
              TextField(
                controller: amtC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Commission amount',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                title: const Text('Active'),
                subtitle: const Text('Off stops this band being used.'),
                onChanged: (v) => setDialogState(() => active = v),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final min = int.tryParse(minC.text.trim());
                final maxText = maxC.text.trim();
                final max = maxText.isEmpty ? null : int.tryParse(maxText);
                final amount = int.tryParse(amtC.text.trim());
                String? problem;
                if (min == null || min < 0) {
                  problem = 'Min receipt total must be 0 or more';
                } else if (maxText.isNotEmpty && max == null) {
                  problem = 'Max receipt total must be a number';
                } else if (max != null && max < min) {
                  problem = 'Max receipt total must be the same as or larger than min';
                } else if (amount == null || amount < 1) {
                  problem = 'Commission amount must be 1 MMK or more';
                } else {
                  problem = _overlapError(min, max, rule?.id);
                }
                if (problem != null) {
                  setDialogState(() => error = problem);
                  return;
                }
                Navigator.pop(ctx, _RuleForm(min!, max, amount!, active));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String? _overlapError(int min, int? max, String? ignoreId) {
    for (final other in _rules) {
      if (other.id == ignoreId) continue;
      final overlaps =
          (max == null || other.minAmount <= max) &&
          (other.maxAmount == null || min <= other.maxAmount!);
      if (overlaps) {
        return 'Overlaps ${fmtMMK(other.minAmount)} – '
            '${other.maxAmount == null ? '∞' : fmtMMK(other.maxAmount!)}';
      }
    }
    return null;
  }

  static String _describe(CommissionRule r) =>
      '${r.minAmount}-${r.maxAmount ?? 'no limit'} -> '
      '${r.commissionAmount} MMK · ${r.active ? 'on' : 'off'}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Commission rules (staff selectable amounts)'),
        Text(
          'Expected commission = rule matching the official receipt total. '
          'Tap a rule to change it. Bands must not overlap, so to add one '
          'between two bands, first shorten the band above it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final r in _rules)
          ListTile(
            dense: true,
            title: Text(
              '${fmtMMK(r.minAmount)} – ${r.maxAmount == null ? '∞' : fmtMMK(r.maxAmount!)}',
            ),
            subtitle: r.active ? null : const Text('Inactive'),
            trailing: Text(
              fmtMMK(r.commissionAmount),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            onTap: () => _edit(r),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('ADD RULE'),
        ),
      ],
    );
  }
}

class _MilestoneRulesSection extends StatefulWidget {
  const _MilestoneRulesSection();

  @override
  State<_MilestoneRulesSection> createState() => _MilestoneRulesSectionState();
}

class _MilestoneRulesSectionState extends State<_MilestoneRulesSection> {
  List<MilestoneRule> _rules = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await AppScope.of(context).milestones.rules();
    if (mounted) setState(() => _rules = rules);
  }

  Future<void> _add() async {
    final result = await _showForm();
    if (result == null) return;
    final s = AppScope.of(context);
    try {
      final rule = await s.milestones.addRule(
        everyN: result.everyN,
        rewardAmount: result.amount,
        active: result.active,
      );
      await s.audit.record(
        'MILESTONE_RULE_ADDED',
        refId: rule.id,
        newValue: _describe(rule),
      );
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _load();
  }

  /// Amount, delivery count and on/off are the admin's to set. Rewards already
  /// earned keep the amount they were created with.
  Future<void> _edit(MilestoneRule rule) async {
    final result = await _showForm(rule: rule);
    if (result == null) return;
    final s = AppScope.of(context);
    final updated = MilestoneRule(
      id: rule.id,
      everyN: result.everyN,
      rewardAmount: result.amount,
      active: result.active,
    );
    try {
      await s.milestones.updateRule(updated);
      await s.audit.record(
        'MILESTONE_RULE_CHANGED',
        refId: rule.id,
        oldValue: _describe(rule),
        newValue: _describe(updated),
      );
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
    await _load();
  }

  /// One dialog for both adding and editing, with validation kept inside so a
  /// mistake does not close the form.
  Future<_MilestoneForm?> _showForm({MilestoneRule? rule}) async {
    final everyC = TextEditingController(
      text: rule == null ? '' : '${rule.everyN}',
    );
    final amountC = TextEditingController(
      text: rule == null ? '' : '${rule.rewardAmount}',
    );
    var active = rule?.active ?? true;
    String? error;
    return showDialog<_MilestoneForm>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            rule == null ? 'New milestone reward' : 'Milestone reward',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: everyC,
                autofocus: rule == null,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Every N deliveries',
                ),
              ),
              TextField(
                controller: amountC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Reward amount (MMK)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                title: const Text('Active'),
                subtitle: const Text(
                  'Off stops new rewards; earned ones are kept.',
                ),
                onChanged: (v) => setDialogState(() => active = v),
              ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final everyN = int.tryParse(everyC.text.trim());
                final amount = int.tryParse(amountC.text.trim());
                String? problem;
                if (everyN == null || everyN < 1) {
                  problem = 'Every N deliveries must be 1 or more';
                } else if (amount == null || amount < 1) {
                  problem = 'Reward amount must be 1 MMK or more';
                } else if (_rules.any(
                  (r) => r.everyN == everyN && r.id != rule?.id,
                )) {
                  problem =
                      'A rule for every $everyN deliveries already exists';
                }
                if (problem != null) {
                  setDialogState(() => error = problem);
                  return;
                }
                Navigator.pop(ctx, _MilestoneForm(everyN!, amount!, active));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  static String _describe(MilestoneRule r) =>
      'every ${r.everyN} -> ${r.rewardAmount} MMK · ${r.active ? 'on' : 'off'}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Milestone rewards'),
        Text(
          'A reward is created automatically on delivery #N, #2N, … of each '
          'rule. Earned rewards keep the amount they were created with.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final r in _rules)
          ListTile(
            dense: true,
            title: Text('Every ${r.everyN} deliveries'),
            subtitle: r.active ? null : const Text('Inactive'),
            trailing: Text(
              fmtMMK(r.rewardAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.amber[800],
              ),
            ),
            onTap: () => _edit(r),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _add,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('ADD REWARD RULE'),
        ),
      ],
    );
  }
}

class _MilestoneForm {
  const _MilestoneForm(this.everyN, this.amount, this.active);
  final int everyN;
  final int amount;
  final bool active;
}

class _UsersSection extends StatefulWidget {
  const _UsersSection();

  @override
  State<_UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<_UsersSection> {
  List<User> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await AppScope.of(context).users.all();
    if (mounted) setState(() => _users = users);
  }

  Future<void> _editPin(User user) async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Login PIN for ${user.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Use 4 to 8 digits. Only the admin can change it.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'New login PIN',
                counterText: '',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;
    final clean = entered.trim();
    if (clean.length < 4 || clean.length > 8 || int.tryParse(clean) == null) {
      showMessage(context, 'PIN must be 4 to 8 digits', error: true);
      return;
    }
    if (clean == user.pin) {
      showMessage(context, 'That is already the PIN for ${user.name}');
      return;
    }
    final approved = await askAdminPin(
      context,
      reason: 'Change the login PIN for ${user.name}?',
    );
    if (!approved || !mounted) return;
    final services = AppScope.of(context);
    await services.users.update(user.copyWith(pin: clean));
    await services.audit.record('USER_PIN_CHANGED', refId: user.id);
    await _load();
    if (mounted) showMessage(context, 'Login PIN changed for ${user.name}');
  }

  @override
  Widget build(BuildContext context) {
    final stillDefault = _users.any((u) => u.isAdmin && u.pin == '1234');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Users'),
        Text(
          'Sensitive actions (delete, take a payment back, correct) ask for the '
          'Admin PIN, so staff never need a daily code or an email. Tap a user '
          'to change their login PIN.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (stillDefault)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'The Admin PIN is still the default 1234. Change it now.',
              style: TextStyle(color: Colors.red),
            ),
          ),
        for (final u in _users)
          ListTile(
            dense: true,
            leading: const Icon(Icons.person),
            title: Text(u.name),
            subtitle: Text('${u.role.name} · login PIN ${u.pin}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (u.isAdmin) const Chip(label: Text('ADMIN')),
                IconButton(
                  tooltip: 'Change login PIN',
                  onPressed: () => _editPin(u),
                  icon: const Icon(Icons.key, size: 18),
                ),
              ],
            ),
            onTap: () => _editPin(u),
          ),
      ],
    );
  }
}

class _ReconSettingsSection extends StatefulWidget {
  const _ReconSettingsSection();

  @override
  State<_ReconSettingsSection> createState() => _ReconSettingsSectionState();
}

class _ReconSettingsSectionState extends State<_ReconSettingsSection> {
  late final TextEditingController _gapHours;

  @override
  void initState() {
    super.initState();
    _gapHours = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final v = await AppScope.of(context).settings
        .get(SettingsRepository.reconTimeGapHoursKey);
    if (mounted) {
      _gapHours.text =
          v ?? '${SettingsRepository.defaultReconTimeGapHours.round()}';
    }
  }

  @override
  void dispose() {
    _gapHours.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _gapHours.text.trim();
    final hours = double.tryParse(text);
    if (hours == null || hours < 0) {
      showMessage(context, 'Enter a number of hours', error: true);
      return;
    }
    await AppScope.of(context).settings
        .set(SettingsRepository.reconTimeGapHoursKey, text);
    showMessage(context, 'Reconciliation time-gap threshold saved');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Reconciliation'),
        Text(
          'A detailed result is flagged OVER when commission was entered more '
          'than this many hours after the receipt date/time.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _gapHours,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Time gap warning (hours)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _save, child: const Text('SAVE')),
      ],
    );
  }
}

class _SheetsConfigSection extends StatefulWidget {
  const _SheetsConfigSection();

  @override
  State<_SheetsConfigSection> createState() => _SheetsConfigSectionState();
}

class _SheetsConfigSectionState extends State<_SheetsConfigSection> {
  late TextEditingController _spreadsheet;
  late TextEditingController _serviceAccountJson;
  late TextEditingController _sheet;
  late bool _configured;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final c = AppScope.of(context).sheets.config;
    _spreadsheet = TextEditingController(text: c.spreadsheetId);
    _serviceAccountJson = TextEditingController(text: c.serviceAccountJson);
    _sheet = TextEditingController(text: c.sheetName);
    _configured = c.isConfigured;
  }

  @override
  void dispose() {
    _spreadsheet.dispose();
    _serviceAccountJson.dispose();
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = AppScope.of(context);
    await s.saveSheetsConfig(
      s.sheets.config.copyWith(
        spreadsheetId: _spreadsheet.text.trim(),
        serviceAccountJson: _serviceAccountJson.text.trim(),
        sheetName: _sheet.text.trim().isEmpty
            ? 'CommissionRecords'
            : _sheet.text.trim(),
      ),
    );
    showMessage(context, 'Sheets configuration saved');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Google Sheets credentials'),
        TextField(
          controller: _spreadsheet,
          decoration: const InputDecoration(
            labelText: 'Spreadsheet ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _serviceAccountJson,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Service account JSON (paste full key file contents)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _sheet,
          decoration: const InputDecoration(
            labelText: 'Commission sheet name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _save,
          child: Text(_configured ? 'UPDATE CONFIG' : 'SAVE CONFIG'),
        ),
      ],
    );
  }
}

class _RuleForm {
  const _RuleForm(this.min, this.max, this.amount, this.active);
  final int min;
  final int? max;
  final int amount;
  final bool active;
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<AuditLog> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await AppScope.of(context).audit.logs();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Audit Log',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
          ? const EmptyState(message: 'No audit entries yet.')
          : ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (ctx, i) {
                final l = _logs[i];
                return ListTile(
                  leading: const Icon(Icons.fact_check),
                  title: Text(l.action),
                  subtitle: Text(
                    '${l.userName} · ${l.createdLocal}'
                    '${l.refId == null ? '' : '\nRef: ${l.refId}'}'
                    '${l.newValue == null ? '' : '\n→ ${l.newValue}'}',
                  ),
                  isThreeLine: true,
                );
              },
            ),
    );
  }
}
