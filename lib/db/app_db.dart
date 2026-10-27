import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

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
  ];

  Future<void> open() async {
    if (_db != null) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'dukandar.db');
    _db = await openDatabase(path, version: 1, onCreate: _create);
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
    await db.execute('CREATE INDEX idx_batches_product ON batches(product_id)');
    await db.execute('CREATE INDEX idx_sales_product ON sales(product_id)');
    await db.execute('CREATE INDEX idx_sales_sold ON sales(sold_at)');
    await db.execute(
        'CREATE INDEX idx_payments_credit ON credit_payments(credit_id)');
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
