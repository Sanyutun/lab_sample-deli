import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where this office terminal keeps its data.
///
/// Empty ([local]) means the terminal uses its own database and can host the
/// LAN server. A configured link means the terminal is a *client* of another
/// office terminal: all data comes from that server over the LAN.
///
/// The link is stored in a small file next to the app, not in the database —
/// the database may be the very thing the link points at.
class OfficeLink {
  const OfficeLink({this.url = '', this.key = '', this.terminalId = ''});

  /// Base URL of the host terminal's server, e.g. `http://192.168.1.5:8787`.
  final String url;

  /// The office link key the host terminal displays.
  final String key;

  /// Random id that keeps this terminal's staff session separate from other
  /// terminals sharing the same database.
  final String terminalId;

  bool get isConfigured => url.trim().isNotEmpty && key.trim().isNotEmpty;

  static const OfficeLink local = OfficeLink();
  static const String _fileName = 'office_link.json';

  OfficeLink copyWith({String? url, String? key, String? terminalId}) =>
      OfficeLink(
        url: url ?? this.url,
        key: key ?? this.key,
        terminalId: terminalId ?? this.terminalId,
      );

  static Future<OfficeLink> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return local;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return local;
      return OfficeLink(
        url: (decoded['url'] as String?) ?? '',
        key: (decoded['key'] as String?) ?? '',
        terminalId: (decoded['terminalId'] as String?) ?? '',
      );
    } catch (_) {
      // A missing or damaged config must never block startup.
      return local;
    }
  }

  /// Saves [link], minting a terminal id the first time. Returns what was saved.
  static Future<OfficeLink> save(OfficeLink link) async {
    final saved = link.terminalId.isEmpty
        ? link.copyWith(terminalId: _newTerminalId())
        : link;
    final file = await _file();
    await file.writeAsString(
      jsonEncode({
        'url': saved.url.trim(),
        'key': saved.key.trim(),
        'terminalId': saved.terminalId,
      }),
    );
    return saved;
  }

  /// Forgets the link, so the terminal falls back to its own database.
  static Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  static String _newTerminalId() {
    final rng = Random.secure();
    return List<int>.generate(
      9,
      (_) => rng.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, _fileName));
  }
}
