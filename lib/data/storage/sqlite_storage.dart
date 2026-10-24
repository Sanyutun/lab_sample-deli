import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

import 'app_storage.dart';

class SqliteStorage implements AppStorage {
  SqliteStorage._(this._db);

  final Database _db;

  static Future<SqliteStorage> open({String? dbPath}) async {
    final path = dbPath ?? await _defaultDbPath();
    final db = await openDatabase(
      path,
      version: 12,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return SqliteStorage._(db);
  }

  /// Desktop has no sqflite plugin, so use the FFI factory (native sqlite3
  /// bundled by sqlite3_flutter_libs) and keep the file under the app's own
  /// support directory. Android/iOS keep the plugin's default database path.
  static Future<String> _defaultDbPath() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final dir = await getApplicationSupportDirectory();
      return p.join(dir.path, 'lab_commission.db');
    }
    return p.join(await getDatabasesPath(), 'lab_commission.db');
  }

  static Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE official_receipts ADD COLUMN refer TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE reconciliation_results ADD COLUMN refer TEXT',
      );
    }
    if (oldVersion < 3) {
      await db.execute('DROP TABLE IF EXISTS daily_closings');
      await _createMonthlyClosings(db);
    }
    if (oldVersion < 4) {
      await _createCompanionTables(db);
    }
    if (oldVersion < 5) {
      await db.execute(
        'ALTER TABLE delivery_men ADD COLUMN require_qr INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 8) {
      await db.execute(
        'ALTER TABLE reconciliation_results ADD COLUMN commission_at INTEGER',
      );
    }
    // v4/v5 installs already have delivery_locations without client_id. An
    // install older than v4 just created the table above with the column
    // already in it, so only v4/v5 need the ALTER.
    if (oldVersion >= 4 && oldVersion < 6) {
      await db.execute(
        'ALTER TABLE delivery_locations ADD COLUMN client_id TEXT',
      );
      await db.execute(
        'CREATE UNIQUE INDEX idx_delivery_locations_client '
        'ON delivery_locations(delivery_man_id, client_id)',
      );
    }
    if (oldVersion < 7) {
      // Retention needs the office's own receipt time, which a phone with a
      // wrong clock cannot influence.
      await db.execute(
        'ALTER TABLE delivery_locations ADD COLUMN received_at INTEGER NOT NULL DEFAULT 0',
      );
      await db.execute(
        'UPDATE delivery_locations SET received_at = captured_at WHERE received_at = 0',
      );
      await _createTripPoints(db);
    }
    if (oldVersion < 9) {
      await _createDeliveryCalls(db);
    }
    if (oldVersion < 10) {
      await db.execute(
        "ALTER TABLE official_receipts ADD COLUMN patient TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE reconciliation_results ADD COLUMN patient TEXT',
      );
    }
    if (oldVersion < 11) {
      await _createPrintedReceipts(db);
    }
    if (oldVersion < 12) {
      await db.execute(
        "ALTER TABLE users ADD COLUMN email TEXT NOT NULL DEFAULT ''",
      );
      await _createDailyPins(db);
    }
  }

  /// Today's action PIN per user, replaced when the day rolls.
  static Future<void> _createDailyPins(Database db) async {
    await db.execute('''
      CREATE TABLE daily_pins (
        user_id TEXT PRIMARY KEY,
        pin TEXT NOT NULL,
        date TEXT NOT NULL,
        generated_at INTEGER NOT NULL
      )
    ''');
  }

  /// What the print spooler read off each receipt, kept by barcode.
  static Future<void> _createPrintedReceipts(Database db) async {
    await db.execute('''
      CREATE TABLE printed_receipts (
        barcode TEXT PRIMARY KEY,
        patient TEXT NOT NULL DEFAULT '',
        age_sex TEXT NOT NULL DEFAULT '',
        refer TEXT NOT NULL DEFAULT '',
        receipt_date TEXT NOT NULL DEFAULT '',
        total_amount TEXT NOT NULL DEFAULT '',
        detected_at INTEGER NOT NULL
      )
    ''');
  }

  /// Incoming calls from delivery men, kept as commission evidence.
  static Future<void> _createDeliveryCalls(Database db) async {
    await db.execute('''
      CREATE TABLE delivery_calls (
        id TEXT PRIMARY KEY,
        delivery_man_id TEXT NOT NULL,
        phone TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        answered INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Routes preserved for delivered receipts. A copy of the fixes, so deleting
  /// the raw 20-minute history never loses a route that was already saved.
  static Future<void> _createTripPoints(Database db) async {
    await db.execute('''
      CREATE TABLE delivery_trip_points (
        id TEXT PRIMARY KEY,
        barcode TEXT NOT NULL,
        commission_id TEXT NOT NULL,
        delivery_man_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy_m REAL,
        captured_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        source_id TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_trip_points_barcode '
      'ON delivery_trip_points(barcode, captured_at)',
    );
    await db.execute(
      'CREATE INDEX idx_trip_points_commission '
      'ON delivery_trip_points(commission_id)',
    );
  }

  /// Companion-app tables (accounts, sessions, GPS fixes). Added in schema v4;
  /// existing office data is untouched, so old installs keep working.
  static Future<void> _createCompanionTables(Database db) async {
    await db.execute('''
      CREATE TABLE delivery_man_accounts (
        id TEXT PRIMARY KEY,
        delivery_man_id TEXT NOT NULL UNIQUE,
        login_id TEXT NOT NULL UNIQUE,
        pin_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        qr_token_hash TEXT,
        qr_issued_at INTEGER,
        created_at INTEGER NOT NULL,
        last_login_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE delivery_sessions (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        revoked_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE delivery_locations (
        id TEXT PRIMARY KEY,
        delivery_man_id TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy_m REAL,
        captured_at INTEGER NOT NULL,
        received_at INTEGER NOT NULL DEFAULT 0,
        barcode TEXT,
        client_id TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_delivery_locations_dm ON delivery_locations(delivery_man_id, captured_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_delivery_locations_client '
      'ON delivery_locations(delivery_man_id, client_id)',
    );
    await _createTripPoints(db);
  }

  static Future<void> _createMonthlyClosings(Database db) async {
    await db.execute('''
      CREATE TABLE monthly_closings (
        id TEXT PRIMARY KEY,
        month TEXT NOT NULL,
        opening_balance INTEGER NOT NULL,
        cash_received INTEGER NOT NULL,
        commission_earned INTEGER NOT NULL,
        commission_paid INTEGER NOT NULL,
        rewards_paid INTEGER NOT NULL,
        other_payments INTEGER NOT NULL,
        other_income INTEGER NOT NULL,
        expected_remaining INTEGER NOT NULL,
        actual_counted INTEGER NOT NULL,
        difference INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        counted_by TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_closing_month ON monthly_closings(month)',
    );
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        pin TEXT NOT NULL,
        role TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        email TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE delivery_men (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1,
        require_qr INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE commission_rules (
        id TEXT PRIMARY KEY,
        min_amount INTEGER NOT NULL,
        max_amount INTEGER,
        commission_amount INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE commission_records (
        id TEXT PRIMARY KEY,
        barcode TEXT NOT NULL,
        delivery_man_id TEXT NOT NULL,
        commission INTEGER NOT NULL,
        date_time INTEGER NOT NULL,
        staff_user_id TEXT NOT NULL,
        status TEXT NOT NULL,
        payment_status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        reversed_at INTEGER,
        reversed_by TEXT,
        reversal_reason TEXT,
        paid_at INTEGER,
        paid_by TEXT
      )
    ''');
    await db.execute(
      "CREATE UNIQUE INDEX idx_active_barcode ON commission_records(barcode) WHERE status = 'active'",
    );
    await db.execute('''
      CREATE TABLE milestone_rules (
        id TEXT PRIMARY KEY,
        every_n INTEGER NOT NULL,
        reward_amount INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE milestone_rewards (
        id TEXT PRIMARY KEY,
        delivery_man_id TEXT NOT NULL,
        every_n INTEGER NOT NULL,
        milestone_count INTEGER NOT NULL,
        reward_amount INTEGER NOT NULL,
        status TEXT NOT NULL,
        payment_status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        paid_at INTEGER,
        paid_by TEXT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX idx_milestone ON milestone_rewards(delivery_man_id, every_n, milestone_count)',
    );
    await db.execute('''
      CREATE TABLE cash_advances (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        amount INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cash_transactions (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        ref_type TEXT,
        ref_id TEXT,
        date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE official_receipts (
        id TEXT PRIMARY KEY,
        barcode TEXT NOT NULL,
        receipt_date TEXT NOT NULL,
        total_amount INTEGER NOT NULL,
        batch_id TEXT NOT NULL,
        imported_at INTEGER NOT NULL,
        refer TEXT NOT NULL DEFAULT '',
        patient TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_official_barcode ON official_receipts(barcode)',
    );
    await db.execute('''
      CREATE TABLE reconciliation_results (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        barcode TEXT NOT NULL,
        receipt_amount INTEGER,
        delivery_man_id TEXT,
        entered_commission INTEGER,
        expected_commission INTEGER,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        delivery_man_name TEXT,
        receipt_date TEXT,
        refer TEXT,
        patient TEXT,
        commission_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE reconciliation_runs (
        id TEXT PRIMARY KEY,
        official_count INTEGER NOT NULL,
        staff_count INTEGER NOT NULL,
        match_count INTEGER NOT NULL,
        mismatch_count INTEGER NOT NULL,
        not_found_count INTEGER NOT NULL,
        duplicate_count INTEGER NOT NULL,
        unclaimed_count INTEGER NOT NULL,
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE commission_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        action TEXT NOT NULL,
        ref_id TEXT,
        old_value TEXT,
        new_value TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await _createDeliveryCalls(db);
    await _createMonthlyClosings(db);
    await _createCompanionTables(db);
    await _createPrintedReceipts(db);
    await _createDailyPins(db);
  }

  static (String, List<dynamic>) _where(Map<String, dynamic>? where) {
    if (where == null || where.isEmpty) return ('1=1', const []);
    final parts = <String>[];
    final args = <dynamic>[];
    where.forEach((k, v) {
      parts.add('"$k" = ?');
      args.add(v);
    });
    return (parts.join(' AND '), args);
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> insert(String table, Map<String, dynamic> row) async {
    await _db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  @override
  Future<void> insertMany(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<Map<String, dynamic>>> find(
    String table, {
    Map<String, dynamic>? where,
    String? orderBy,
  }) {
    final (clause, args) = _where(where);
    return _db.query(table, where: clause, whereArgs: args, orderBy: orderBy);
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
    final (clause, args) = _where(where);
    await _db.update(table, values, where: clause, whereArgs: args);
  }

  @override
  Future<void> remove(String table, Map<String, dynamic> where) async {
    final (clause, args) = _where(where);
    await _db.delete(table, where: clause, whereArgs: args);
  }

  @override
  Future<void> clear(String table) async {
    await _db.delete(table);
  }
}
