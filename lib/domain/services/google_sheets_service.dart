import 'dart:async';
import 'dart:convert';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../../data/backup_schema.dart';
import '../../data/models/models.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/storage/app_storage.dart';
import '../exceptions.dart';
import 'audit_service.dart';

/// Configuration for Google Sheets integration.
/// Service account JSON is pasted in Admin Settings — no credentials are embedded in code.
class GoogleSheetsConfig {
  const GoogleSheetsConfig({
    this.spreadsheetId = '',
    this.sheetName = 'CommissionRecords',
    this.reconciliationSheetName = 'Reconciliation',
    this.serviceAccountJson = '',
  });

  final String spreadsheetId;
  final String sheetName;
  final String reconciliationSheetName;

  /// Full service-account key JSON (the contents of the .json key file).
  final String serviceAccountJson;

  bool get isConfigured =>
      spreadsheetId.isNotEmpty && serviceAccountJson.isNotEmpty;

  GoogleSheetsConfig copyWith({
    String? spreadsheetId,
    String? sheetName,
    String? reconciliationSheetName,
    String? serviceAccountJson,
  }) => GoogleSheetsConfig(
    spreadsheetId: spreadsheetId ?? this.spreadsheetId,
    sheetName: sheetName ?? this.sheetName,
    reconciliationSheetName:
        reconciliationSheetName ?? this.reconciliationSheetName,
    serviceAccountJson: serviceAccountJson ?? this.serviceAccountJson,
  );
}

/// Transport abstraction so credentials/HTTP implementation can be plugged in later.
abstract class SheetsClient {
  Future<void> appendRows({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  });

  /// Replaces the whole worksheet (clears it, then writes [rows] from A1).
  Future<void> overwrite({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  });

  /// Reads every populated cell of a worksheet (cell values as strings).
  Future<List<List<String>>> read({
    required String spreadsheetId,
    required String sheetName,
  });

  /// Existing worksheet (tab) titles in the spreadsheet.
  Future<List<String>> sheetTitles({required String spreadsheetId});

  /// Creates any of [titles] that do not exist yet.
  Future<void> addSheets({
    required String spreadsheetId,
    required List<String> titles,
  });
}

/// Throws until real API credentials are configured.
class UnconfiguredSheetsClient implements SheetsClient {
  const UnconfiguredSheetsClient();

  @override
  Future<void> appendRows({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    throw const SheetsNotConfiguredException();
  }

  @override
  Future<void> overwrite({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    throw const SheetsNotConfiguredException();
  }

  @override
  Future<List<List<String>>> read({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    throw const SheetsNotConfiguredException();
  }

  @override
  Future<List<String>> sheetTitles({required String spreadsheetId}) async {
    throw const SheetsNotConfiguredException();
  }

  @override
  Future<void> addSheets({
    required String spreadsheetId,
    required List<String> titles,
  }) async {
    throw const SheetsNotConfiguredException();
  }
}

/// Real client: service-account JWT → OAuth2 access token → Google Sheets REST API.
class ServiceAccountSheetsClient implements SheetsClient {
  ServiceAccountSheetsClient({required this.serviceAccountJson});

  /// Parsed contents of the service-account .json key file.
  final String serviceAccountJson;

  static const String _base = 'https://sheets.googleapis.com/v4/spreadsheets';

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/spreadsheets',
  ];

  AuthClient? _authClient;

  Future<http.Client> _authed() async {
    if (_authClient != null) return _authClient!;
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(serviceAccountJson) as Map<String, dynamic>;
    } on FormatException {
      throw const AppException('Service account JSON is not valid JSON.');
    }
    try {
      final credentials = ServiceAccountCredentials.fromJson(json);
      _authClient = await clientViaServiceAccount(credentials, _scopes);
    } catch (e) {
      throw AppException('Failed to authenticate with Google: $e');
    }
    return _authClient!;
  }

  Uri _valuesUri(String spreadsheetId, String sheetName) => Uri.parse(
    '$_base/$spreadsheetId/values/${Uri.encodeComponent(sheetName)}',
  );

  void _check(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppException(
        'Sheets API error ${response.statusCode}: ${response.body}',
      );
    }
  }

  @override
  Future<void> appendRows({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    final client = await _authed();
    final uri =
        Uri.parse(
          '$_base/$spreadsheetId/values/'
          '${Uri.encodeComponent(sheetName)}:append',
        ).replace(
          queryParameters: {
            'valueInputOption': 'RAW',
            'insertDataOption': 'INSERT_ROWS',
          },
        );

    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'values': rows}),
    );
    _check(response);
  }

  @override
  Future<void> overwrite({
    required String spreadsheetId,
    required String sheetName,
    required List<List<Object?>> rows,
  }) async {
    final client = await _authed();
    // Clear first so stale trailing rows from a previous, larger backup vanish.
    final clearUri = Uri.parse(
      '$_base/$spreadsheetId/values/'
      '${Uri.encodeComponent(sheetName)}:clear',
    );
    final clearResponse = await client.post(clearUri);
    _check(clearResponse);

    final updateUri = _valuesUri(
      spreadsheetId,
      sheetName,
    ).replace(queryParameters: {'valueInputOption': 'RAW'});
    final updateResponse = await client.put(
      updateUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'values': rows}),
    );
    _check(updateResponse);
  }

  @override
  Future<List<List<String>>> read({
    required String spreadsheetId,
    required String sheetName,
  }) async {
    final client = await _authed();
    final uri = _valuesUri(
      spreadsheetId,
      sheetName,
    ).replace(queryParameters: {'valueRenderOption': 'UNFORMATTED_VALUE'});
    final response = await client.get(uri);
    if (response.statusCode == 400) {
      // Range not found → treat as empty worksheet.
      return const [];
    }
    _check(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final values = (json['values'] as List?) ?? const [];
    return [
      for (final row in values)
        [for (final cell in (row as List)) cell?.toString() ?? ''],
    ];
  }

  @override
  Future<List<String>> sheetTitles({required String spreadsheetId}) async {
    final client = await _authed();
    final uri = Uri.parse('$_base/$spreadsheetId')
        .replace(queryParameters: {'fields': 'sheets.properties.title'});
    final response = await client.get(uri);
    _check(response);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final sheets = (json['sheets'] as List?) ?? const [];
    return [
      for (final s in sheets)
        ((s as Map<String, dynamic>)['properties']
                    as Map<String, dynamic>?)?['title']
                ?.toString() ??
            '',
    ].where((t) => t.isNotEmpty).toList();
  }

  @override
  Future<void> addSheets({
    required String spreadsheetId,
    required List<String> titles,
  }) async {
    final existing = (await sheetTitles(spreadsheetId: spreadsheetId)).toSet();
    final missing = titles.where((t) => !existing.contains(t)).toList();
    if (missing.isEmpty) return;

    final client = await _authed();
    final uri = Uri.parse('$_base/$spreadsheetId:batchUpdate');
    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requests': [
          for (final title in missing)
            {
              'addSheet': {
                'properties': {'title': title},
              },
            },
        ],
      }),
    );
    _check(response);
  }

  void close() {
    _authClient?.close();
    _authClient = null;
  }
}

class BackupResult {
  const BackupResult({required this.tables, required this.rows});

  final int tables;
  final int rows;
}

class RestoreResult {
  const RestoreResult({required this.tables, required this.rows});

  final int tables;
  final int rows;
}

class GoogleSheetsService {
  GoogleSheetsService({
    required this.storage,
    required this.commissions,
    required this.receipts,
    required this.audit,
    required this.client,
    this.config = const GoogleSheetsConfig(),
  }) {
    _startHourlyBackup();
  }

  final AppStorage storage;
  final CommissionRepository commissions;
  final ReceiptRepository receipts;
  final AuditService audit;
  SheetsClient client;
  GoogleSheetsConfig config;
  Timer? _hourlyBackupTimer;

  static const List<String> commissionHeaders = [
    'Transaction ID',
    'Barcode',
    'Delivery Man ID',
    'Delivery Man Name',
    'Commission',
    'DateTime',
    'Staff ID',
    'Status',
    'Payment Status',
  ];

  static const List<String> reconciliationHeaders = [
    'Barcode',
    'Patient',
    'Receipt Amount',
    'Refer',
    'Delivery Man',
    'Entered Commission',
    'Expected Commission',
    'Status',
  ];

  List<List<Object?>> buildCommissionRows(List<CommissionRecord> records) {
    final rows = <List<Object?>>[List<Object?>.from(commissionHeaders)];
    for (final r in records) {
      rows.add([
        r.id,
        r.barcode,
        r.deliveryManId,
        r.deliveryManName ?? '',
        r.commission,
        r.dateTimeLocal,
        r.staffUserId,
        r.status.name,
        r.paymentStatus.name,
      ]);
    }
    return rows;
  }

  List<List<Object?>> buildReconciliationRows(
    List<ReconciliationResult> results,
  ) {
    final rows = <List<Object?>>[List<Object?>.from(reconciliationHeaders)];
    for (final r in results) {
      rows.add([
        r.barcode,
        r.patient.isEmpty ? '--' : r.patient,
        r.receiptAmount ?? '--',
        r.refer.isEmpty ? '--' : r.refer,
        r.deliveryManName ?? r.deliveryManId ?? '--',
        r.enteredCommission ?? '--',
        r.expectedCommission ?? '--',
        r.statusLabel,
      ]);
    }
    return rows;
  }

  Future<void> syncCommissionRecords({List<CommissionRecord>? records}) async {
    _requireConfig();
    final list = records ?? await commissions.all();
    await client.appendRows(
      spreadsheetId: config.spreadsheetId,
      sheetName: config.sheetName,
      rows: buildCommissionRows(list),
    );
    await audit.record(
      'SHEETS_SYNC_COMMISSIONS',
      newValue: '${list.length} rows',
    );
  }

  Future<void> syncReconciliation({
    required String runId,
    required List<ReconciliationResult> results,
  }) async {
    _requireConfig();
    await client.appendRows(
      spreadsheetId: config.spreadsheetId,
      sheetName: config.reconciliationSheetName,
      rows: buildReconciliationRows(results),
    );
    await audit.record(
      'SHEETS_SYNC_RECONCILIATION',
      refId: runId,
      newValue: '${results.length} rows',
    );
  }

  /// Uploads every table as its own worksheet tab. This is a full snapshot:
  /// each tab is overwritten, so re-running it never duplicates data.
  Future<BackupResult> backupAll() async {
    _requireConfig();
    await client.addSheets(
      spreadsheetId: config.spreadsheetId,
      titles: [for (final t in backupTables) t.name],
    );

    var totalRows = 0;
    for (final table in backupTables) {
      final stored = await storage.find(table.name);
      final rows = stored.where((r) => !_isExcludedRow(table, r)).toList();
      final cells = <List<Object?>>[
        table.headers,
        for (final r in rows) encodeRow(r, table),
      ];
      await client.overwrite(
        spreadsheetId: config.spreadsheetId,
        sheetName: table.name,
        rows: cells,
      );
      totalRows += rows.length;
    }

    await audit.record(
      'SHEETS_BACKUP',
      newValue: '${backupTables.length} tables, $totalRows rows',
    );
    return BackupResult(tables: backupTables.length, rows: totalRows);
  }

  /// Restores every worksheet tab back into local storage, replacing the local
  /// contents of each table. Tabs that are missing from the sheet are skipped
  /// (their local data is left untouched).
  Future<RestoreResult> restoreAll() async {
    _requireConfig();
    final titles = (await client.sheetTitles(
      spreadsheetId: config.spreadsheetId,
    )).toSet();

    var restoredTables = 0;
    var totalRows = 0;
    for (final table in backupTables) {
      if (!titles.contains(table.name)) continue;
      final values = await client.read(
        spreadsheetId: config.spreadsheetId,
        sheetName: table.name,
      );
      if (values.isEmpty) continue;

      final header = values.first;
      final maps = <Map<String, dynamic>>[];
      for (final row in values.skip(1)) {
        if (row.every((c) => c.trim().isEmpty)) continue;
        final map = decodeRow(header, row, table);
        if (_isExcludedRow(table, map)) continue;
        maps.add(map);
      }

      await storage.clear(table.name);
      for (final map in maps) {
        await storage.insert(table.name, map);
      }
      restoredTables++;
      totalRows += maps.length;
    }

    await audit.record(
      'SHEETS_RESTORE',
      newValue: '$restoredTables tables, $totalRows rows',
    );
    return RestoreResult(tables: restoredTables, rows: totalRows);
  }

  void _startHourlyBackup() {
    _hourlyBackupTimer?.cancel();
    _hourlyBackupTimer = Timer.periodic(const Duration(hours: 1), (_) async {
      if (!config.isConfigured) return;
      try {
        await backupAll();
      } catch (_) {
        // Best effort hourly backup; ignore failures.
      }
    });
  }

  void dispose() {
    _hourlyBackupTimer?.cancel();
    _hourlyBackupTimer = null;
  }

  /// Secrets (Google Sheets credentials) are never uploaded, and are ignored if
  /// found in a sheet being restored.
  bool _isExcludedRow(BackupTable table, Map<String, dynamic> row) {
    if (table.name != 'commission_settings') return false;
    final key = row['key']?.toString() ?? '';
    return backupExcludedSettingPrefixes.any(key.startsWith);
  }

  void _requireConfig() {
    if (!config.isConfigured) throw const SheetsNotConfiguredException();
  }
}
