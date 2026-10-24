import 'package:sqflite/sqflite.dart';

/// One GPS fix captured on this phone, and whether the office already has it.
///
/// [id] is assigned by the phone and sent to the office, so a send that failed
/// after the office stored the fix is recognised on retry instead of being
/// recorded twice.
class QueuedFix {
  const QueuedFix({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
    this.accuracyM,
    this.transferred = false,
  });

  final String id;
  final double latitude;
  final double longitude;
  final int capturedAt;
  final double? accuracyM;
  final bool transferred;

  Map<String, Object?> toMap() => {
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracyM,
    'captured_at': capturedAt,
    'transferred': transferred ? 1 : 0,
  };

  factory QueuedFix.fromMap(Map<String, Object?> m) => QueuedFix(
    id: m['id'] as String,
    latitude: (m['latitude'] as num).toDouble(),
    longitude: (m['longitude'] as num).toDouble(),
    capturedAt: (m['captured_at'] as num).toInt(),
    accuracyM: m['accuracy_m'] == null
        ? null
        : (m['accuracy_m'] as num).toDouble(),
    transferred: (m['transferred'] as int? ?? 0) == 1,
  );
}

/// On-device backlog of GPS fixes. Lives here, not on the office server, so a
/// fix survives a lost connection; [markTransferred] records what the office
/// has acknowledged.
abstract class LocationQueue {
  Future<void> init();

  Future<void> add(QueuedFix fix);

  /// Oldest first, so the office receives them in the order they happened.
  Future<List<QueuedFix>> pending({int limit = 500});

  /// Newest first, for display. Includes fixes the office already has.
  Future<List<QueuedFix>> recent({int limit = 100});

  Future<void> markTransferred(List<String> ids);

  Future<int> countPending();

  /// Deletes fixes that the office has already acknowledged and that were
  /// captured before [cutoffMs]. Fixes still waiting to be sent are never
  /// deleted — they are what survives a long offline stretch — so an unsent
  /// backlog can outlive the retention window and still reach the office.
  Future<int> purgeTransferredBefore(int cutoffMs);

  Future<void> clear();
}

class SqliteLocationQueue implements LocationQueue {
  SqliteLocationQueue({this.fileName = 'companion_locations.db'});

  final String fileName;
  Database? _db;

  static const String _table = 'fixes';

  @override
  Future<void> init() async {
    final db = await openDatabase(
      '${await getDatabasesPath()}/$fileName',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            accuracy_m REAL,
            captured_at INTEGER NOT NULL,
            transferred INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_fixes_pending ON $_table(transferred, captured_at)',
        );
      },
    );
    _db = db;
  }

  Database get _database {
    final db = _db;
    if (db == null) throw StateError('LocationQueue.init() was not awaited');
    return db;
  }

  @override
  Future<void> add(QueuedFix fix) async {
    await _database.insert(
      _table,
      fix.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<List<QueuedFix>> pending({int limit = 500}) async {
    final rows = await _database.query(
      _table,
      where: 'transferred = 0',
      orderBy: 'captured_at ASC',
      limit: limit,
    );
    return [for (final r in rows) QueuedFix.fromMap(r)];
  }

  @override
  Future<List<QueuedFix>> recent({int limit = 100}) async {
    final rows = await _database.query(
      _table,
      orderBy: 'captured_at DESC',
      limit: limit,
    );
    return [for (final r in rows) QueuedFix.fromMap(r)];
  }

  @override
  Future<void> markTransferred(List<String> ids) async {
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    await _database.update(
      _table,
      {'transferred': 1},
      where: 'id IN ($marks)',
      whereArgs: ids,
    );
  }

  @override
  Future<int> countPending() async {
    final rows = await _database.rawQuery(
      'SELECT COUNT(*) AS n FROM $_table WHERE transferred = 0',
    );
    return (rows.first['n'] as num).toInt();
  }

  @override
  Future<int> purgeTransferredBefore(int cutoffMs) => _database.delete(
    _table,
    where: 'transferred = 1 AND captured_at < ?',
    whereArgs: [cutoffMs],
  );

  @override
  Future<void> clear() async {
    await _database.delete(_table);
  }
}

/// In-memory queue for tests.
class MemoryLocationQueue implements LocationQueue {
  final List<QueuedFix> _fixes = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> add(QueuedFix fix) async {
    if (_fixes.any((f) => f.id == fix.id)) return;
    _fixes.add(fix);
  }

  @override
  Future<List<QueuedFix>> pending({int limit = 500}) async {
    final list = _fixes.where((f) => !f.transferred).toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return list.take(limit).toList();
  }

  @override
  Future<List<QueuedFix>> recent({int limit = 100}) async {
    final list = [..._fixes]..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return list.take(limit).toList();
  }

  @override
  Future<void> markTransferred(List<String> ids) async {
    for (var i = 0; i < _fixes.length; i++) {
      if (ids.contains(_fixes[i].id)) {
        _fixes[i] = QueuedFix(
          id: _fixes[i].id,
          latitude: _fixes[i].latitude,
          longitude: _fixes[i].longitude,
          capturedAt: _fixes[i].capturedAt,
          accuracyM: _fixes[i].accuracyM,
          transferred: true,
        );
      }
    }
  }

  @override
  Future<int> countPending() async => _fixes.where((f) => !f.transferred).length;

  @override
  Future<int> purgeTransferredBefore(int cutoffMs) async {
    final before = _fixes.length;
    _fixes.removeWhere(
      (f) => f.transferred && f.capturedAt < cutoffMs,
    );
    return before - _fixes.length;
  }

  @override
  Future<void> clear() async => _fixes.clear();
}
