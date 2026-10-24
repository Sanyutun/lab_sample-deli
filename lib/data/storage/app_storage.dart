/// Storage abstraction. The app's primary database is local (SQLite on device);
/// tests and tooling use [MemoryStorage]. Repositories are written once
/// against this interface.
abstract class AppStorage {
  Future<void> init();

  Future<void> insert(String table, Map<String, dynamic> row);

  /// Inserts many rows in a single transaction/batch. Used for bulk writes
  /// (e.g. reconciliation results) where per-row inserts would be too slow.
  Future<void> insertMany(String table, List<Map<String, dynamic>> rows);

  Future<List<Map<String, dynamic>>> find(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
  });

  Future<Map<String, dynamic>?> findOne(
    String table,
    Map<String, dynamic> where,
  );

  Future<void> update(
    String table,
    Map<String, dynamic> where,
    Map<String, dynamic> values,
  );

  Future<void> remove(String table, Map<String, dynamic> where);

  Future<void> clear(String table);
}

class MemoryStorage implements AppStorage {
  final Map<String, List<Map<String, dynamic>>> _tables = {};

  @override
  Future<void> init() async {}

  List<Map<String, dynamic>> _table(String name) =>
      _tables.putIfAbsent(name, () => []);

  static bool _matches(Map<String, dynamic> row, Map<String, dynamic> where) {
    for (final entry in where.entries) {
      if (row[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  Future<void> insert(String table, Map<String, dynamic> row) async {
    _table(table).add(Map<String, dynamic>.from(row));
  }

  @override
  Future<void> insertMany(String table, List<Map<String, dynamic>> rows) async {
    final t = _table(table);
    for (final row in rows) {
      t.add(Map<String, dynamic>.from(row));
    }
  }

  @override
  Future<List<Map<String, dynamic>>> find(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
  }) async {
    var rows = _table(table)
        .where((r) => where == null || _matches(r, where))
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    if (orderBy != null) rows = _sort(rows, orderBy);
    return rows;
  }

  List<Map<String, dynamic>> _sort(
    List<Map<String, dynamic>> rows,
    String orderBy,
  ) {
    final desc = orderBy.trim().startsWith('-');
    final key = orderBy.replaceFirst(RegExp(r'^-'), '').trim();
    rows.sort((a, b) {
      final av = a[key];
      final bv = b[key];
      int cmp;
      if (av is Comparable && bv is Comparable) {
        cmp = av.compareTo(bv);
      } else {
        cmp = 0;
      }
      return desc ? -cmp : cmp;
    });
    return rows;
  }

  @override
  Future<Map<String, dynamic>?> findOne(
    String table,
    Map<String, dynamic> where,
  ) async {
    final rows = await find(table, where: where);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> update(
    String table,
    Map<String, dynamic> where,
    Map<String, dynamic> values,
  ) async {
    for (final row in _table(table)) {
      if (_matches(row, where)) row.addAll(values);
    }
  }

  @override
  Future<void> remove(String table, Map<String, dynamic> where) async {
    _table(table).removeWhere((r) => _matches(r, where));
  }

  @override
  Future<void> clear(String table) async {
    _table(table).clear();
  }
}
