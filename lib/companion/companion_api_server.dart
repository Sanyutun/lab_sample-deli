import 'dart:convert';
import 'dart:io';

import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../domain/exceptions.dart';
import '../domain/services/companion_service.dart';
import 'store_gateway.dart';

/// A tiny HTTP server that exposes the office database to companion apps on the
/// same network. It is the *only* gate between the two apps: every request is
/// authorised here from the bearer token, and the delivery man id is taken from
/// the session — never from the request body.
///
/// On the companion surface financial writes are impossible: no route creates
/// or edits a commission, payment, reward or rule. The only other surface is the
/// office data gateway ([ApiRoutes.store]), which is key-guarded and lets a
/// second office terminal run its repositories against this database.
class CompanionApiServer {
  CompanionApiServer({required this.service, this.gateway, this.port = 8787});

  final CompanionService service;

  /// Office-to-office data gateway. Null disables those routes entirely.
  final StoreGateway? gateway;

  final int port;

  HttpServer? _server;

  bool get isRunning => _server != null;
  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    server.listen(_onRequest, onError: (_) {}, cancelOnError: false);
    _server = server;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      final method = request.method.toUpperCase();
      final path = request.uri.path;

      if (method == 'POST' && path == ApiRoutes.login) {
        final body = await _readJson(request);
        final session = await service.login(
          loginId: (body['loginId'] as String?) ?? '',
          pin: (body['pin'] as String?) ?? '',
        );
        return await _json(request, HttpStatus.ok, session.toJson());
      }

      if (method == 'POST' && path == ApiRoutes.logout) {
        await service.logout(_bearer(request));
        return await _json(request, HttpStatus.ok, {'ok': true});
      }

      if (method == 'POST' && path == ApiRoutes.verifyQr) {
        final body = await _readJson(request);
        final token =
            (body['token'] as String?) ??
            tokenFromQrPayload((body['payload'] as String?) ?? '');
        final profile = await service.verifyQr(token);
        if (profile == null) {
          return await _error(request, HttpStatus.notFound, 'unknown_qr');
        }
        return await _json(request, HttpStatus.ok, profile.toJson());
      }

      // Office-to-office data gateway: a second office terminal running its
      // repositories against this database. Guarded by the office link key,
      // separate from every delivery-man route below.
      if (path.startsWith('${ApiRoutes.store}/')) {
        final gateway = this.gateway;
        final key = gateway == null ? null : await gateway.officeKey;
        if (gateway == null || key == null || key.isEmpty) {
          // No key yet: behave as if the route does not exist.
          return await _error(request, HttpStatus.notFound, 'not_found');
        }
        if (_bearer(request) != key) {
          return await _error(request, HttpStatus.unauthorized, 'unauthorized');
        }
        final op = path.substring('${ApiRoutes.store}/'.length);
        try {
          final body = await _readJson(request);
          return await _json(
            request,
            HttpStatus.ok,
            await gateway.handle(op, body),
          );
        } on StoreRequestException catch (e) {
          return await _error(
            request,
            HttpStatus.badRequest,
            'invalid_request',
            message: e.message,
          );
        }
      }

      // Everything below requires a valid delivery-man session.
      final identity = await service.authenticate(_bearer(request));
      final manId = identity.man.id;

      if (method == 'GET' && path == ApiRoutes.me) {
        return await _json(
          request,
          HttpStatus.ok,
          (await service.profile(identity)).toJson(),
        );
      }

      if (method == 'GET' && path == ApiRoutes.summary) {
        return await _json(
          request,
          HttpStatus.ok,
          (await service.summary(manId)).toJson(),
        );
      }

      if (method == 'GET' && path == ApiRoutes.gpsPolicy) {
        return await _json(
          request,
          HttpStatus.ok,
          (await service.gpsPolicy()).toJson(),
        );
      }

      if (method == 'GET' && path == ApiRoutes.commissions) {
        final q = request.uri.queryParameters;
        final list = await service.listCommissions(
          manId,
          from: q['from'],
          to: q['to'],
          paymentStatus: q['status'],
        );
        return await _json(request, HttpStatus.ok, {
          'items': [for (final c in list) c.toJson()],
        });
      }

      if (method == 'GET' && path.startsWith('${ApiRoutes.commissions}/')) {
        final id = Uri.decodeComponent(
          path.substring('${ApiRoutes.commissions}/'.length),
        );
        final detail = await service.commissionDetail(manId, id);
        if (detail == null) {
          return await _error(request, HttpStatus.notFound, 'not_found');
        }
        return await _json(request, HttpStatus.ok, detail.toJson());
      }

      if (method == 'GET' && path == ApiRoutes.rewards) {
        final list = await service.listRewards(manId);
        return await _json(request, HttpStatus.ok, {
          'items': [for (final r in list) r.toJson()],
        });
      }

      if (method == 'GET' && path == ApiRoutes.deliveryBoard) {
        return await _json(
          request,
          HttpStatus.ok,
          (await service.deliveryBoard(manId)).toJson(),
        );
      }

      if ((method == 'GET' || method == 'POST') && path == ApiRoutes.qr) {
        // Issuing a code rotates it: the previous code stops working.
        final qr = await service.rotateQr(identity.account.id);
        return await _json(request, HttpStatus.ok, qr.toJson());
      }

      if (method == 'POST' && path == ApiRoutes.qrRotate) {
        final qr = await service.rotateQr(identity.account.id);
        return await _json(request, HttpStatus.ok, qr.toJson());
      }

      if (method == 'GET' && path == ApiRoutes.locations) {
        final list = await service.listLocations(manId);
        return await _json(request, HttpStatus.ok, {
          'items': [for (final l in list) l.toJson()],
        });
      }

      // A man's own preserved route for a receipt he delivered.
      if (method == 'GET' && path.startsWith('${ApiRoutes.trips}/')) {
        final barcode = Uri.decodeComponent(
          path.substring('${ApiRoutes.trips}/'.length),
        );
        final trip = await service.tripHistory(manId, barcode);
        if (trip == null) {
          return await _error(request, HttpStatus.notFound, 'not_found');
        }
        return await _json(request, HttpStatus.ok, trip.toJson());
      }

      if (method == 'POST' && path == ApiRoutes.locations) {
        final body = await _readJson(request);
        final lat = (body['latitude'] as num?)?.toDouble();
        final lng = (body['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) {
          return await _error(
            request,
            HttpStatus.badRequest,
            'missing_coordinates',
          );
        }
        final point = await service.recordLocation(
          manId,
          latitude: lat,
          longitude: lng,
          accuracyM: (body['accuracyM'] as num?)?.toDouble(),
          capturedAt: (body['capturedAt'] as num?)?.toInt(),
          barcode: body['barcode'] as String?,
          clientId: body['clientId'] as String?,
        );
        return await _json(request, HttpStatus.created, point.toJson());
      }

      return await _error(request, HttpStatus.notFound, 'not_found');
    } on AppException catch (e) {
      return await _error(
        request,
        _statusFor(e),
        _codeFor(e),
        message: e.message,
      );
    } on FormatException {
      return await _error(request, HttpStatus.badRequest, 'bad_request');
    } catch (_) {
      return await _error(
        request,
        HttpStatus.internalServerError,
        'server_error',
      );
    }
  }

  // ---------- helpers ----------

  int _statusFor(AppException e) => switch (e) {
    PermissionDeniedException() => HttpStatus.unauthorized,
    NotFoundException() => HttpStatus.notFound,
    ValidationException() => HttpStatus.badRequest,
    _ => HttpStatus.badRequest,
  };

  String _codeFor(AppException e) => switch (e) {
    PermissionDeniedException() => 'unauthorized',
    NotFoundException() => 'not_found',
    ValidationException() => 'invalid_request',
    _ => 'error',
  };

  String? _bearer(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null) return null;
    if (header.startsWith(bearerPrefix)) {
      return header.substring(bearerPrefix.length).trim();
    }
    return header.trim();
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Expected a JSON object');
  }

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    final response = request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _error(
    HttpRequest request,
    int status,
    String code, {
    String message = '',
  }) => _json(request, status, {
    'error': ApiErrorDto(
      code: code,
      message: message.isEmpty ? code : message,
    ).toJson(),
  });
}

/// Non-loopback IPv4 addresses of this device, so staff can read out the URL a
/// companion app should point at.
Future<List<String>> localServerAddresses() async {
  final addresses = <String>[];
  try {
    for (final iface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    )) {
      for (final addr in iface.addresses) {
        addresses.add(addr.address);
      }
    }
  } on Exception {
    // Ignore: the UI falls back to asking the user for the IP manually.
  }
  return addresses;
}
