/// QR identity + credential hashing rules shared by both apps.
///
/// The QR code carries only an opaque, revocable token — never a name, phone,
/// commission, payment or password. The office verifies the token's hash against
/// the shared backend before it assigns a receipt.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Prefix that marks a payload as a version-1 companion QR token. Versioning the
/// payload lets the office reject or migrate older formats safely.
const String qrPayloadPrefix = 'lc1';

final Random _rng = Random.secure();

/// Cryptographically random, URL-safe opaque token.
String randomToken([int byteLength = 32]) {
  final bytes = List<int>.generate(byteLength, (_) => _rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Random per-account salt (hex).
String newSalt([int byteLength = 16]) => sha256Hex(randomToken(byteLength));

/// SHA-256 digest as lowercase hex. Used for PINs (salted) and opaque tokens.
String sha256Hex(String input) =>
    sha256.convert(utf8.encode(input)).toString();

/// Salted PIN digest. A salted hash means a leaked file does not reveal PINs and
/// two users with the same PIN store different digests.
String hashPin(String pin, String salt) => sha256Hex('$salt:$pin');

/// Wraps a raw token into the QR payload drawn on screen.
String qrPayloadFor(String token) => '$qrPayloadPrefix:$token';

/// Extracts the raw token from a scanned payload, or null when the payload is
/// not a companion QR (so the office scanner can fall back to a receipt barcode).
String? tokenFromQrPayload(String payload) {
  final trimmed = payload.trim();
  final prefix = '$qrPayloadPrefix:';
  if (!trimmed.startsWith(prefix)) return null;
  final token = trimmed.substring(prefix.length);
  return token.isEmpty ? null : token;
}
