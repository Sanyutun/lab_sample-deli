import '../data/storage/config_store.dart';

/// App-wide settings the delivery man can change, currently just the address of
/// the office sync server. No secrets are stored here.
class AppConfig {
  AppConfig(this._store);

  final ConfigStore _store;
  String _serverUrl = '';

  String get serverUrl => _serverUrl;
  bool get isConfigured => _serverUrl.isNotEmpty;

  Future<void> load() async {
    _serverUrl = _normalize((await _store.readServerUrl()) ?? '');
  }

  Future<void> saveServerUrl(String url) async {
    _serverUrl = _normalize(url);
    await _store.writeServerUrl(_serverUrl);
  }

  /// Parses a scanned office "setup QR" payload into a server URL, or null when
  /// it does not look like one. The office encodes `http://<ip>:<port>`, so a
  /// port is required — that rejects unrelated QR codes.
  static String? serverUrlFromQr(String payload) {
    final normalized = _normalize(payload);
    if (normalized.isEmpty) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
    return normalized;
  }

  /// Accepts "192.168.1.20:8787" or a full URL and normalises it.
  static String _normalize(String url) {
    var value = url.trim();
    if (value.isEmpty) return '';
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
