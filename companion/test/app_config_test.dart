import 'package:flutter_test/flutter_test.dart';
import 'package:lab_delivery_companion/core/app_config.dart';

void main() {
  test('serverUrlFromQr accepts an office setup code', () {
    expect(
      AppConfig.serverUrlFromQr('http://192.168.1.20:8787'),
      'http://192.168.1.20:8787',
    );
    // Bare host:port is accepted too.
    expect(
      AppConfig.serverUrlFromQr('192.168.1.20:8787'),
      'http://192.168.1.20:8787',
    );
  });

  test('serverUrlFromQr rejects payloads that are not setup codes', () {
    expect(AppConfig.serverUrlFromQr(''), isNull);
    expect(AppConfig.serverUrlFromQr('hello'), isNull);
    // No port — not the shape the office encodes.
    expect(AppConfig.serverUrlFromQr('http://example.com'), isNull);
  });
}
