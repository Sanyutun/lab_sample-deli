import 'dart:convert';
import 'dart:math';

import '../data/repositories/settings_repository.dart';
import '../data/storage/app_storage.dart';

/// Raised for a malformed store request or a table outside the schema.
class StoreRequestException implements Exception {
  StoreRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Office-to-office data gateway.
///
/// Lets a second office terminal run its repositories against *this* terminal's
/// database over the LAN, so a shop can have more than one office terminal on
/// one dataset. It is deliberately narrow:
///
///  * only tables the app itself creates can be touched ([tables]);
///  * row and where values are handed to the storage layer unchanged, so they
///    are always bound parameters, never interpolated into SQL;
///  * `orderBy` is validated before it reaches the database;
///  * access needs the office link key, which lives in the settings table.
///
/// Business rules are *not* enforced here — the client runs the same services as
/// the host. Two terminals editing the same receipt at the same instant is
/// therefore still possible; keep one office terminal as the operator.
class StoreGateway {
  StoreGateway(this.storage, this.settings);

  final AppStorage storage;
  final SettingsRepository settings;

  static const String officeKeySetting = 'office.linkKey';

  /// The tables the app creates. A request naming anything else is rejected.
  static const Set<String> tables = {
    'users',
    'delivery_men',
    'commission_rules',
    'commission_records',
    'milestone_rules',
    'milestone_rewards',
    'cash_advances',
    'cash_transactions',
    'official_receipts',
    'reconciliation_results',
    'reconciliation_runs',
    'commission_settings',
    'audit_logs',
    'monthly_closings',
    'delivery_man_accounts',
    'delivery_sessions',
    'delivery_locations',
    'delivery_trip_points',
    'delivery_calls',
    'printed_receipts',
    'daily_pins',
  };

  /// `column`, `column ASC/DESC`, comma-separated. Blocks SQL punctuation while
  /// allowing every order-by the app actually uses.
  static final RegExp _orderByPattern = RegExp(
    r'^-?[A-Za-z0-9_]+(?: +(?:ASC|DESC|asc|desc))?(?: *, *-?[A-Za-z0-9_]+(?: +(?:ASC|DESC|asc|desc))?)*$',
  );

  Future<String?> get officeKey => settings.get(officeKeySetting);

  /// The key a host terminal hands to its office clients. Created on first use.
  Future<String> ensureOfficeKey() async {
    final existing = await officeKey;
    if (existing != null && existing.isNotEmpty) return existing;
    return regenerateOfficeKey();
  }

  /// Issues a fresh key. Every already-configured client must be updated.
  Future<String> regenerateOfficeKey() async {
    final rng = Random.secure();
    final key = base64Url
        .encode(List<int>.generate(24, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
    await settings.set(officeKeySetting, key);
    return key;
  }

  /// Runs one storage operation and returns the JSON body to send back.
  Future<Map<String, dynamic>> handle(
    String op,
    Map<String, dynamic> body,
  ) async {
    final table = _table(body);
    switch (op) {
      case 'insert':
        await storage.insert(table, _map(body['row'], 'row'));
        return const {'ok': true};
      case 'insertMany':
        final raw = body['rows'];
        if (raw is! List) throw StoreRequestException('rows must be a list');
        await storage.insertMany(table, [
          for (final row in raw) _map(row, 'rows'),
        ]);
        return const {'ok': true};
      case 'find':
        final rows = await storage.find(
          table,
          where: _whereOrNull(body['where']),
          orderBy: _orderByOrNull(body['orderBy']),
        );
        return {'rows': rows};
      case 'findOne':
        return {'row': await storage.findOne(table, _where(body['where']))};
      case 'update':
        await storage.update(
          table,
          _where(body['where']),
          _map(body['values'], 'values'),
        );
        return const {'ok': true};
      case 'remove':
        await storage.remove(table, _where(body['where']));
        return const {'ok': true};
      case 'clear':
        await storage.clear(table);
        return const {'ok': true};
    }
    throw StoreRequestException('unknown operation: $op');
  }

  String _table(Map<String, dynamic> body) {
    final table = body['table'];
    if (table is! String || !tables.contains(table)) {
      throw StoreRequestException('unknown table');
    }
    return table;
  }

  Map<String, dynamic> _map(Object? value, String field) {
    if (value is! Map) throw StoreRequestException('$field must be an object');
    return Map<String, dynamic>.from(value);
  }

  Map<String, dynamic> _where(Object? value) => _map(value, 'where');

  Map<String, dynamic>? _whereOrNull(Object? value) =>
      value == null ? null : _map(value, 'where');

  String? _orderByOrNull(Object? value) {
    if (value == null) return null;
    if (value is! String || !_orderByPattern.hasMatch(value)) {
      throw StoreRequestException('invalid orderBy');
    }
    return value;
  }
}
