import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' as ffiweb;

/// Local SQLite database. Everything is saved here first, so the app works
/// with no internet. The SyncService copies changes to/from the cloud.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;
  Database get db => _db!;

  /// Order matters only for readability; there are no foreign keys.
  static const List<String> syncTables = [
    'products',
    'batches',
    'sales',
    'credits',
    'credit_payments',
    'bills',
  ];

  Future<void> open() async {
    if (_db != null) return;
    if (kIsWeb) {
      // Browser: SQLite runs as WebAssembly and saves into the browser's
      // IndexedDB, so the data stays on this computer and works offline.
      // Needs web/sqlite3.wasm and web/sqflite_sw.js (made by the build).
      databaseFactory = ffiweb.databaseFactoryFfiWeb;
      _db = await openDatabase('dukandar_web.db', version: 2, onCreate: _create, onUpgrade: _upgrade);
      return;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'dukandar.db');
    _db = await openDatabase(path, version: 2, onCreate: _create, onUpgrade: _upgrade);
  }

  static const String _common =
      'shop_id TEXT, updated_at TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, synced INTEGER NOT NULL DEFAULT 0';

  Future<void> _create(Database db, int version) async {
    await db.execute('''
CREATE TABLE products (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  subcategory TEXT,
  brand TEXT,
  model TEXT,
  created_at TEXT NOT NULL,
  $_common
)''');
    await db.execute('''
CREATE TABLE batches (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  qty INTEGER NOT NULL,
  unit_cost REAL NOT NULL,
  serial TEXT,
  purchased_at TEXT NOT NULL,
  created_by TEXT,
  $_common
)''');
    await db.execute('''
CREATE TABLE sales (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  qty INTEGER NOT NULL,
  unit_price REAL NOT NULL,
  unit_cost REAL NOT NULL,
  extra_cost REAL NOT NULL DEFAULT 0,
  customer TEXT,
  note TEXT,
  credit_id TEXT,
  sold_at TEXT NOT NULL,
  created_by TEXT,
  bill_id TEXT NOT NULL DEFAULT '',
  list_price REAL,
  item_name TEXT NOT NULL DEFAULT '',
  $_common
)''');
    await db.execute('''
CREATE TABLE credits (
  id TEXT PRIMARY KEY,
  sale_id TEXT,
  product_id TEXT NOT NULL,
  product_name TEXT,
  customer_name TEXT NOT NULL,
  phone TEXT,
  qty INTEGER NOT NULL,
  total_due REAL NOT NULL,
  taken_at TEXT NOT NULL,
  expected_date TEXT NOT NULL,
  note TEXT,
  created_by TEXT,
  $_common
)''');
    await db.execute('''
CREATE TABLE credit_payments (
  id TEXT PRIMARY KEY,
  credit_id TEXT NOT NULL,
  amount REAL NOT NULL,
  paid_at TEXT NOT NULL,
  created_by TEXT,
  $_common
)''');
    await _createBills(db);
    await db.execute('CREATE INDEX idx_sales_bill ON sales(bill_id)');
    await db.execute('CREATE INDEX idx_batches_product ON batches(product_id)');
    await db.execute('CREATE INDEX idx_sales_product ON sales(product_id)');
    await db.execute('CREATE INDEX idx_sales_sold ON sales(sold_at)');
    await db.execute(
        'CREATE INDEX idx_payments_credit ON credit_payments(credit_id)');
  }

  Future<void> _createBills(Database db) async {
    await db.execute('''
CREATE TABLE bills (
  id TEXT PRIMARY KEY,
  bill_no TEXT NOT NULL,
  customer TEXT,
  phone TEXT,
  note TEXT,
  discount REAL NOT NULL DEFAULT 0,
  total REAL NOT NULL DEFAULT 0,
  credit_id TEXT NOT NULL DEFAULT '',
  billed_at TEXT NOT NULL,
  created_by TEXT,
  $_common
)''');
    await db.execute('CREATE INDEX idx_bills_at ON bills(billed_at)');
  }

  /// Version 1 -> 2: bills with many items, repair lines and a discount.
  /// Old sales stay exactly as they were (each one shows as a one-item bill).
  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE sales ADD COLUMN bill_id TEXT NOT NULL DEFAULT ''");
      await db.execute('ALTER TABLE sales ADD COLUMN list_price REAL');
      await db.execute("ALTER TABLE sales ADD COLUMN item_name TEXT NOT NULL DEFAULT ''");
      await _createBills(db);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_bill ON sales(bill_id)');
    }
  }

  /// Removes all shop data from this device (used when a different shop
  /// signs in on the same device).
  Future<void> wipe() async {
    for (final t in syncTables) {
      await db.delete(t);
    }
  }

  Future<int> pendingCount() async {
    var total = 0;
    for (final t in syncTables) {
      final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $t WHERE synced = 0');
      total += (r.first['c'] as int?) ?? 0;
    }
    return total;
  }

  /// All rows of all tables, for the "Backup now" file.
  Future<Map<String, Object?>> exportAll() async {
    final out = <String, Object?>{
      'app': 'DukanDar',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
    };
    for (final t in syncTables) {
      out[t] = await db.query(t);
    }
    return out;
  }
}
