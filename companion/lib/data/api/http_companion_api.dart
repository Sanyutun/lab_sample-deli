import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../../core/failure.dart';
import '../../core/strings.dart';
import 'companion_api.dart';

/// Talks to the office sync server over HTTP. The bearer token is held here and
/// attached to every call; the server — not this app — decides what the token
/// may read.
class HttpCompanionApi implements CompanionApi {
  HttpCompanionApi({
    required this.baseUrlProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  /// Read lazily so changing the server address in Settings takes effect at once.
  final String Function() baseUrlProvider;
  final http.Client _client;
  final Duration timeout;

  @override
  String? token;

  @override
  Future<AuthSessionDto> login({
    required String loginId,
    required String pin,
  }) async {
    final body = await _send(
      'POST',
      _uri(ApiRoutes.login),
      body: {'loginId': loginId, 'pin': pin},
    );
    return AuthSessionDto.fromJson(body);
  }

  @override
  Future<void> logout() async {
    await _send('POST', _uri(ApiRoutes.logout));
  }

  @override
  Future<DeliveryManProfileDto> me() async =>
      DeliveryManProfileDto.fromJson(await _send('GET', _uri(ApiRoutes.me)));

  @override
  Future<SummaryDto> summary() async =>
      SummaryDto.fromJson(await _send('GET', _uri(ApiRoutes.summary)));

  @override
  Future<List<CommissionDto>> commissions({
    String? from,
    String? to,
    String? status,
  }) async {
    final query = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (status != null && status.isNotEmpty && status != 'all')
        'status': status,
    };
    final body = await _send(
      'GET',
      _uri(ApiRoutes.commissions, query.isEmpty ? null : query),
    );
    return [
      for (final item in (body['items'] as List? ?? const []))
        CommissionDto.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<CommissionDto> commission(String id) async => CommissionDto.fromJson(
    await _send('GET', _uri(ApiRoutes.commission(id))),
  );

  @override
  Future<List<RewardDto>> rewards() async {
    final body = await _send('GET', _uri(ApiRoutes.rewards));
    return [
      for (final item in (body['items'] as List? ?? const []))
        RewardDto.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<DeliveryBoardDto> deliveryBoard() async => DeliveryBoardDto.fromJson(
    await _send('GET', _uri(ApiRoutes.deliveryBoard)),
  );

  @override
  Future<QrIdentityDto> qr() async =>
      QrIdentityDto.fromJson(await _send('GET', _uri(ApiRoutes.qr)));

  @override
  Future<GpsPolicyDto> gpsPolicy() async =>
      GpsPolicyDto.fromJson(await _send('GET', _uri(ApiRoutes.gpsPolicy)));

  @override
  Future<List<GeoPointDto>> locations() async {
    final body = await _send('GET', _uri(ApiRoutes.locations));
    return [
      for (final item in (body['items'] as List? ?? const []))
        GeoPointDto.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<GeoPointDto> recordLocation({
    required double latitude,
    required double longitude,
    double? accuracyM,
    int? capturedAt,
    String? barcode,
    String? clientId,
  }) async {
    final body = await _send(
      'POST',
      _uri(ApiRoutes.locations),
      body: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyM': ?accuracyM,
        'capturedAt': ?capturedAt,
        if (barcode != null && barcode.isNotEmpty) 'barcode': barcode,
        if (clientId != null && clientId.isNotEmpty) 'clientId': clientId,
      },
    );
    return GeoPointDto.fromJson(body);
  }

  // ---------- plumbing ----------

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrlProvider().trim();
    if (base.isEmpty) {
      throw const ApiFailure('no_server', S.errNoServer);
    }
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final uri = Uri.parse('$normalized$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri, {
    Object? body,
  }) async {
    http.Response response;
    try {
      final request = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const OfflineFailure(S.errTimeout);
    } on SocketException {
      throw const OfflineFailure();
    } on http.ClientException {
      throw const OfflineFailure();
    }

    if (response.statusCode == HttpStatus.unauthorized) {
      throw const UnauthorizedFailure();
    }

    Map<String, dynamic> decoded = const {};
    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw const ApiFailure('bad_response', S.errBadResponse);
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      throw ApiFailure(
        (error['code'] as String?) ?? 'error',
        (error['message'] as String?) ?? S.errRequestFailed,
      );
    }
    throw ApiFailure('error', S.errRequestFailedWithCode(response.statusCode));
  }
}
