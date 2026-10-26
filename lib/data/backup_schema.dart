/// Registry describing every persisted table for Google Sheets backup/restore.
/// Column names match the SQLite columns exactly, and become the header row of
/// each worksheet tab.
library;

enum BackupType { text, integer }

class BackupColumn {
  const BackupColumn(this.name, [this.type = BackupType.text]);

  final String name;
  final BackupType type;
}

class BackupTable {
  const BackupTable(this.name, this.columns);

  /// Sheet tab name and storage table name (identical).
  final String name;
  final List<BackupColumn> columns;

  List<String> get headers => [for (final c in columns) c.name];
}

const List<BackupTable> backupTables = [
  BackupTable('users', [
    BackupColumn('id'),
    BackupColumn('name'),
    BackupColumn('pin'),
    BackupColumn('role'),
    BackupColumn('active', BackupType.integer),
    BackupColumn('email'),
    BackupColumn('last_login_at', BackupType.integer),
  ]),
  BackupTable('delivery_men', [
    BackupColumn('id'),
    BackupColumn('name'),
    BackupColumn('phone'),
    BackupColumn('active', BackupType.integer),
    BackupColumn('created_at', BackupType.integer),
  ]),
  BackupTable('commission_rules', [
    BackupColumn('id'),
    BackupColumn('min_amount', BackupType.integer),
    BackupColumn('max_amount', BackupType.integer),
    BackupColumn('commission_amount', BackupType.integer),
    BackupColumn('active', BackupType.integer),
  ]),
  BackupTable('commission_records', [
    BackupColumn('id'),
    BackupColumn('barcode'),
    BackupColumn('delivery_man_id'),
    BackupColumn('commission', BackupType.integer),
    BackupColumn('date_time', BackupType.integer),
    BackupColumn('staff_user_id'),
    BackupColumn('status'),
    BackupColumn('payment_status'),
    BackupColumn('created_at', BackupType.integer),
    BackupColumn('reversed_at', BackupType.integer),
    BackupColumn('reversed_by'),
    BackupColumn('reversal_reason'),
    BackupColumn('paid_at', BackupType.integer),
    BackupColumn('paid_by'),
  ]),
  BackupTable('milestone_rules', [
    BackupColumn('id'),
    BackupColumn('every_n', BackupType.integer),
    BackupColumn('reward_amount', BackupType.integer),
    BackupColumn('active', BackupType.integer),
  ]),
  BackupTable('milestone_rewards', [
    BackupColumn('id'),
    BackupColumn('delivery_man_id'),
    BackupColumn('every_n', BackupType.integer),
    BackupColumn('milestone_count', BackupType.integer),
    BackupColumn('reward_amount', BackupType.integer),
    BackupColumn('status'),
    BackupColumn('payment_status'),
    BackupColumn('created_at', BackupType.integer),
    BackupColumn('paid_at', BackupType.integer),
    BackupColumn('paid_by'),
  ]),
  BackupTable('cash_advances', [
    BackupColumn('id'),
    BackupColumn('date'),
    BackupColumn('amount', BackupType.integer),
    BackupColumn('note'),
    BackupColumn('created_by'),
    BackupColumn('created_at', BackupType.integer),
  ]),
  BackupTable('cash_transactions', [
    BackupColumn('id'),
    BackupColumn('type'),
    BackupColumn('amount', BackupType.integer),
    BackupColumn('ref_type'),
    BackupColumn('ref_id'),
    BackupColumn('date'),
    BackupColumn('note'),
    BackupColumn('created_by'),
    BackupColumn('created_at', BackupType.integer),
  ]),
  BackupTable('monthly_closings', [
    BackupColumn('id'),
    BackupColumn('month'),
    BackupColumn('opening_balance', BackupType.integer),
    BackupColumn('cash_received', BackupType.integer),
    BackupColumn('commission_earned', BackupType.integer),
    BackupColumn('commission_paid', BackupType.integer),
    BackupColumn('rewards_paid', BackupType.integer),
    BackupColumn('other_payments', BackupType.integer),
    BackupColumn('other_income', BackupType.integer),
    BackupColumn('expected_remaining', BackupType.integer),
    BackupColumn('actual_counted', BackupType.integer),
    BackupColumn('difference', BackupType.integer),
    BackupColumn('note'),
    BackupColumn('counted_by'),
    BackupColumn('created_at', BackupType.integer),
  ]),
  BackupTable('official_receipts', [
    BackupColumn('id'),
    BackupColumn('barcode'),
    BackupColumn('receipt_date'),
    BackupColumn('total_amount', BackupType.integer),
    BackupColumn('batch_id'),
    BackupColumn('imported_at', BackupType.integer),
    BackupColumn('refer'),
    BackupColumn('patient'),
  ]),
  BackupTable('reconciliation_runs', [
    BackupColumn('id'),
    BackupColumn('official_count', BackupType.integer),
    BackupColumn('staff_count', BackupType.integer),
    BackupColumn('match_count', BackupType.integer),
    BackupColumn('mismatch_count', BackupType.integer),
    BackupColumn('not_found_count', BackupType.integer),
    BackupColumn('duplicate_count', BackupType.integer),
    BackupColumn('unclaimed_count', BackupType.integer),
    BackupColumn('created_by'),
    BackupColumn('created_at', BackupType.integer),
  ]),
  BackupTable('reconciliation_results', [
    BackupColumn('id'),
    BackupColumn('run_id'),
    BackupColumn('barcode'),
    BackupColumn('receipt_amount', BackupType.integer),
    BackupColumn('delivery_man_id'),
    BackupColumn('entered_commission', BackupType.integer),
    BackupColumn('expected_commission', BackupType.integer),
    BackupColumn('status'),
    BackupColumn('created_at', BackupType.integer),
    BackupColumn('delivery_man_name'),
    BackupColumn('receipt_date'),
    BackupColumn('refer'),
    BackupColumn('patient'),
    BackupColumn('commission_at', BackupType.integer),
  ]),
  BackupTable('delivery_man_accounts', [
    BackupColumn('id'),
    BackupColumn('delivery_man_id'),
    BackupColumn('login_id'),
    BackupColumn('pin_hash'),
    BackupColumn('salt'),
    BackupColumn('active', BackupType.integer),
    BackupColumn('qr_token_hash'),
    BackupColumn('qr_issued_at', BackupType.integer),
    BackupColumn('created_at', BackupType.integer),
    BackupColumn('last_login_at', BackupType.integer),
  ]),
  BackupTable('delivery_locations', [
    BackupColumn('id'),
    BackupColumn('delivery_man_id'),
    BackupColumn('latitude'),
    BackupColumn('longitude'),
    BackupColumn('accuracy_m'),
    BackupColumn('captured_at', BackupType.integer),
    BackupColumn('received_at', BackupType.integer),
    BackupColumn('barcode'),
    BackupColumn('client_id'),
  ]),
  BackupTable('delivery_trip_points', [
    BackupColumn('id'),
    BackupColumn('barcode'),
    BackupColumn('commission_id'),
    BackupColumn('delivery_man_id'),
    BackupColumn('latitude'),
    BackupColumn('longitude'),
    BackupColumn('accuracy_m'),
    BackupColumn('captured_at', BackupType.integer),
    BackupColumn('created_at', BackupType.integer),
    BackupColumn('source_id'),
  ]),
  BackupTable('audit_logs', [
    BackupColumn('id'),
    BackupColumn('user_id'),
    BackupColumn('user_name'),
    BackupColumn('action'),
    BackupColumn('ref_id'),
    BackupColumn('old_value'),
    BackupColumn('new_value'),
    BackupColumn('created_at', BackupType.integer),
  ]),
  BackupTable('delivery_calls', [
    BackupColumn('id'),
    BackupColumn('delivery_man_id'),
    BackupColumn('phone'),
    BackupColumn('received_at', BackupType.integer),
    BackupColumn('answered', BackupType.integer),
  ]),
  BackupTable('commission_settings', [
    BackupColumn('key'),
    BackupColumn('value'),
  ]),
  BackupTable('printed_receipts', [
    BackupColumn('barcode'),
    BackupColumn('patient'),
    BackupColumn('age_sex'),
    BackupColumn('refer'),
    BackupColumn('receipt_date'),
    BackupColumn('total_amount'),
    BackupColumn('detected_at', BackupType.integer),
  ]),
];

/// Settings keys that must never leave the device (secrets/config).
const List<String> backupExcludedSettingPrefixes = ['sheets.', 'mail.'];

List<Object?> encodeRow(Map<String, dynamic> row, BackupTable table) => [
  for (final c in table.columns) _encodeCell(row[c.name], c.type),
];

Object? _encodeCell(Object? value, BackupType type) {
  if (value == null) return '';
  if (type == BackupType.integer) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? '';
  }
  return value.toString();
}

/// Maps a data row back to a storage map, matching columns by header name so a
/// reordered or extended sheet still restores correctly.
Map<String, dynamic> decodeRow(
  List<String> header,
  List<String> cells,
  BackupTable table,
) {
  final index = <String, int>{
    for (var i = 0; i < header.length; i++) header[i].trim(): i,
  };
  final out = <String, dynamic>{};
  for (final c in table.columns) {
    final i = index[c.name];
    final raw = (i != null && i < cells.length) ? cells[i] : '';
    out[c.name] = _decodeCell(raw, c.type);
  }
  return out;
}

Object? _decodeCell(String raw, BackupType type) {
  final s = raw.trim();
  if (type == BackupType.integer) {
    if (s.isEmpty) return null;
    return int.tryParse(s) ?? double.tryParse(s)?.toInt();
  }
  return raw;
}
