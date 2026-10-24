import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lab_commission_contract/lab_commission_contract.dart';

import 'app_storage.dart';

/// Raised when the office server cannot be reached or refuses a call.
class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// An [AppStorage] whose data lives on **another** office terminal, reached
/// over the LAN through the office data gateway.
///
/// Every method is one HTTP round trip, so the app behaves exactly as it does
/// on a local database — the repositories and services are unchanged. The
/// terminal that runs the server keeps using [SqliteStorage] directly.
class HttpStorage implements AppStorage {
  HttpStorage({
    required String baseUrl,
    required String key,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
       _key = key.trim(),
       _client = client ?? http.Client();

  final String baseUrl;
  final String _key;
  final http.Client _client;
  final Duration timeout;

  /// A local check only; the server is reached on the first real call.
  @override
  Future<void> init() async {}

  @override
  Future<void> insert(String table, Map<String, dynamic> row) async {
    await _post('insert', {'table': table, 'row': row});
  }

  @override
  Future<void> insertMany(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _post('insertMany', {'table': table, 'rows': rows});
  }

  @override
  Future<List<Map<String, dynamic>>> find(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
  }) async {
    final body = await _post('find', {
      'table': table,
      'where': where,
      'orderBy': orderBy,
    });
    final rows = body['rows'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  @override
  Future<Map<String, dynamic>?> findOne(
    String table,
    Map<String, dynamic> where,
  ) async {
    final body = await _post('findOne', {'table': table, 'where': where});
    final row = body['row'];
    return row is Map ? Map<String, dynamic>.from(row) : null;
  }

  @override
  Future<void> update(
    String table,
    Map<String, dynamic> where,
    Map<String, dynamic> values,
  ) async {
    await _post('update', {'table': table, 'where': where, 'values': values});
  }

  @override
  Future<void> remove(String table, Map<String, dynamic> where) async {
    await _post('remove', {'table': table, 'where': where});
  }

  @override
  Future<void> clear(String table) async {
    await _post('clear', {'table': table});
  }

  void close() => _client.close();

  Future<Map<String, dynamic>> _post(
    String op,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl${ApiRoutes.storeOp(op)}');
    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              authHeader: '$bearerPrefix$_key',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on Exception {
      throw StorageException('Cannot reach the office server at $baseUrl');
    }
    if (response.statusCode != 200) {
      throw StorageException(_message(response));
    }
    if (response.body.isEmpty) return const {};
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw StorageException('Unexpected reply from the office server');
  }

  String _message(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } on FormatException {
      // Fall through to a status-based message.
    }
    if (response.statusCode == 401) {
      return 'The office server rejected the link key';
    }
    return 'Office server error (${response.statusCode})';
  }
}
