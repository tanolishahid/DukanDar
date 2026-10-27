import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../db/app_db.dart';
import '../models.dart';
import 'importer.dart';
import 'reminders.dart';
import 'session.dart';

/// All reading and writing of shop data. Every write is saved on the device
/// first and marked "not synced"; the SyncService uploads it later.
class Repo extends ChangeNotifier {
  Repo(this.session);

  final SessionState session;
  final Uuid _uuid = const Uuid();

  /// Set by SyncService so a sync starts shortly after any change.
  VoidCallback? onLocalChange;

  /// Goes up on every change; screens use it to know when to reload.
  int version = 0;

  Database get _db => AppDb.instance.db;

  @override
  void notifyListeners() {
    version++;
    super.notifyListeners();
  }

  /// Called after data arrives from the cloud.
  void refresh() {
    notifyListeners();
    rescheduleReminders();
  }

  void _changed({bool credits = false}) {
    notifyListeners();
    onLocalChange?.call();
    if (credits) rescheduleReminders();
  }

  String _now() => DateTime.now().toUtc().toIso8601String();

  Map<String, Object?> _base() => {
        'id': _uuid.v4(),
        'shop_id': session.shopId,
        'updated_at': _now(),
        'deleted': 0,
        'synced': 0,
      };

  // ------------------------------------------------------------ inventory

  Future<List<ProductStock>> products({
    String query = '',
    String category = '',
    bool inStockOnly = false,
  }) async {
    final where = StringBuffer('p.deleted = 0');
    final args = <Object?>[];
    if (category.isNotEmpty) {
      where.write(' AND p.category = ?');
      args.add(category);
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      where.write(' AND (p.name LIKE ? OR p.brand LIKE ? OR p.model LIKE ? '
          'OR p.subcategory LIKE ? OR EXISTS (SELECT 1 FROM batches sb '
          'WHERE sb.product_id = p.id AND sb.deleted = 0 AND sb.serial LIKE ?))');
      final like = '%$q%';
      args.addAll([like, like, like, like, like]);
    }
    final rows = await _db.rawQuery('''
SELECT p.*,
  COALESCE((SELECT SUM(b.qty) FROM batches b WHERE b.product_id = p.id AND b.deleted = 0), 0) AS bought,
  COALESCE((SELECT SUM(b.qty * b.unit_cost) FROM batches b WHERE b.product_id = p.id AND b.deleted = 0), 0) AS bought_value,
  COALESCE((SELECT SUM(s.qty) FROM sales s WHERE s.product_id = p.id AND s.deleted = 0), 0) AS sold,
  COALESCE((SELECT SUM(s.qty * s.unit_cost) FROM sales s WHERE s.product_id = p.id AND s.deleted = 0), 0) AS sold_cost,
  COALESCE((SELECT b.unit_cost FROM batches b WHERE b.product_id = p.id AND b.deleted = 0 ORDER BY b.purchased_at DESC LIMIT 1), 0) AS last_cost
FROM products p
WHERE $where
ORDER BY p.name COLLATE NOCASE
''', args);
    var list = rows.map(ProductStock.fromMap).toList();
    if (inStockOnly) list = list.where((p) => p.stock > 0).toList();
    return list;
  }

  Future<List<BatchRow>> batchesOf(String productId) async {
    final rows = await _db.query('batches',
        where: 'product_id = ? AND deleted = 0',
        whereArgs: [productId],
        orderBy: 'purchased_at DESC');
    return rows.map(BatchRow.fromMap).toList();
  }

  /// Adds stock. If the product (same name, brand, model, category) already
  /// exists the new purchase becomes another batch of it; otherwise a new
  /// product is created. Returns an error message, or null when saved.
  Future<String?> addPurchase({
    String? existingProductId,
    required String name,
    required String category,
    String subcategory = '',
    String brand = '',
    String model = '',
    required int qty,
    required double unitCost,
    String serial = '',
  }) async {
    if (qty <= 0) return 'Quantity must be at least 1.';
    if (unitCost < 0) return 'Purchase price cannot be negative.';
    final cleanSerial = serial.trim();
    if (cleanSerial.isNotEmpty) {
      if (qty != 1) return 'A serial number belongs to one item. Use quantity 1.';
      final dup = await _db.query('batches',
          where: 'deleted = 0 AND LOWER(serial) = ?',
          whereArgs: [cleanSerial.toLowerCase()],
          limit: 1);
      if (dup.isNotEmpty) return 'This serial number is already in your stock.';
    }

    var productId = existingProductId;
    if (productId == null) {
      final found = await _db.query('products',
          where:
              'deleted = 0 AND category = ? AND LOWER(name) = ? AND LOWER(COALESCE(brand, \'\')) = ? AND LOWER(COALESCE(model, \'\')) = ?',
          whereArgs: [
            category,
            name.trim().toLowerCase(),
            brand.trim().toLowerCase(),
            model.trim().toLowerCase(),
          ],
          limit: 1);
      if (found.isNotEmpty) {
        productId = found.first['id'] as String;
      }
    }

    await _db.transaction((txn) async {
      if (productId == null) {
        final pr = _base();
        productId = pr['id'] as String;
        await txn.insert('products', {
          ...pr,
          'name': name.trim(),
          'category': category,
          'subcategory': subcategory.trim(),
          'brand': brand.trim(),
          'model': model.trim(),
          'created_at': _now(),
        });
      }
      await txn.insert('batches', {
        ..._base(),
        'product_id': productId,
        'qty': qty,
        'unit_cost': unitCost,
        'serial': cleanSerial,
        'purchased_at': _now(),
        'created_by': session.userId,
      });
    });
    _changed();
    return null;
  }

  /// Adds many products at once (from an imported file). Rows that match an
  /// existing product become another batch of it. One save, one sync.
  Future<ImportResult> importRows(List<ImportRow> rows) async {
    final skipped = <String>[];
    var batches = 0;
    var newProducts = 0;
    var units = 0;
    var value = 0.0;

    await _db.transaction((txn) async {
      String keyOf(String cat, String name, String brand, String model) =>
          '$cat|${name.trim().toLowerCase()}|${brand.trim().toLowerCase()}|${model.trim().toLowerCase()}';

      final byKey = <String, String>{};
      final existing = await txn.query('products', where: 'deleted = 0');
      for (final p in existing) {
        byKey[keyOf(strOf(p['category']), strOf(p['name']), strOf(p['brand']),
            strOf(p['model']))] = strOf(p['id']);
      }
      final serials = <String>{};
      final serialRows = await txn.query('batches',
          columns: ['serial'],
          where: "deleted = 0 AND serial IS NOT NULL AND serial != ''");
      for (final r in serialRows) {
        serials.add(strOf(r['serial']).toLowerCase());
      }

      for (final r in rows) {
        final serial = r.serial.trim();
        if (serial.isNotEmpty) {
          if (serials.contains(serial.toLowerCase())) {
            skipped.add('Row ${r.line} (${r.name}): serial number $serial is already in stock');
            continue;
          }
          serials.add(serial.toLowerCase());
        }
        final key = keyOf(r.category, r.name, r.brand, r.model);
        var productId = byKey[key];
        if (productId == null) {
          final pr = _base();
          productId = pr['id'] as String;
          await txn.insert('products', {
            ...pr,
            'name': r.name.trim(),
            'category': r.category,
            'subcategory': r.subcategory,
            'brand': r.brand.trim(),
            'model': r.model.trim(),
            'created_at': _now(),
          });
          byKey[key] = productId;
          newProducts++;
        }
        await txn.insert('batches', {
          ..._base(),
          'product_id': productId,
          'qty': r.qty,
          'unit_cost': r.unitCost,
          'serial': serial,
          'purchased_at': _now(),
          'created_by': session.userId,
        });
        batches++;
        units += r.qty;
        value += r.total;
      }
    });
    if (batches > 0) _changed();
    return ImportResult(
      batches: batches,
      newProducts: newProducts,
      units: units,
      value: value,
      skipped: skipped,
    );
  }

  /// Removes a purchase. Refused if some of its stock was already sold.
  Future<String?> deleteBatch(String batchId) async {
    final rows = await _db.query('batches', where: 'id = ?', whereArgs: [batchId]);
    if (rows.isEmpty) return null;
    final productId = rows.first['product_id'] as String;
    final qty = intOf(rows.first['qty']);
    final list = await products();
    final match = list.where((p) => p.id == productId);
    if (match.isNotEmpty && match.first.stock - qty < 0) {
      return 'Some of this stock was already sold, so it cannot be removed.';
    }
    await _softDelete('batches', batchId);
    _changed();
    return null;
  }

  Future<String?> deleteProduct(String productId) async {
    final list = await products();
    final match = list.where((p) => p.id == productId);
    if (match.isNotEmpty && match.first.stock > 0) {
      return 'This product still has stock. Remove its purchases first.';
    }
    await _softDelete('products', productId);
    _changed();
    return null;
  }

  Future<void> _softDelete(String table, String id) async {
    await _db.update(
      table,
      {'deleted': 1, 'updated_at': _now(), 'synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------- sales

  /// Cost per unit of the next [qty] units, oldest purchase first (FIFO).
  /// Null when there is not enough stock.
  Future<double?> fifoUnitCost(String productId, int qty) async {
    if (qty <= 0) return null;
    final batches = await _db.query('batches',
        where: 'product_id = ? AND deleted = 0',
        whereArgs: [productId],
        orderBy: 'purchased_at ASC');
    final soldRows = await _db.rawQuery(
        'SELECT COALESCE(SUM(qty), 0) AS q FROM sales WHERE product_id = ? AND deleted = 0',
        [productId]);
    var skip = intOf(soldRows.first['q']);
    var need = qty;
    var total = 0.0;
    for (final b in batches) {
      var avail = intOf(b['qty']);
      if (skip >= avail) {
        skip -= avail;
        continue;
      }
      avail -= skip;
      skip = 0;
      final take = need < avail ? need : avail;
      total += take * numOf(b['unit_cost']);
      need -= take;
      if (need == 0) break;
    }
    if (need > 0) return null;
    return total / qty;
  }

  Future<String?> addSale({
    required String productId,
    required int qty,
    required double unitPrice,
    double extraCost = 0,
    String customer = '',
    String note = '',
  }) async {
    if (qty <= 0) return 'Quantity must be at least 1.';
    if (unitPrice < 0) return 'Selling price cannot be negative.';
    final cost = await fifoUnitCost(productId, qty);
    if (cost == null) return 'Not enough stock for this sale.';
    await _db.insert('sales', {
      ..._base(),
      'product_id': productId,
      'qty': qty,
      'unit_price': unitPrice,
      'unit_cost': cost,
      'extra_cost': extraCost,
      'customer': customer.trim(),
      'note': note.trim(),
      'credit_id': '',
      'sold_at': _now(),
      'created_by': session.userId,
    });
    _changed();
    return null;
  }

  Future<String?> deleteSale(String saleId) async {
    final rows = await _db.query('sales', where: 'id = ?', whereArgs: [saleId]);
    if (rows.isNotEmpty && strOf(rows.first['credit_id']).isNotEmpty) {
      return 'This sale was given on credit. Delete it from the Credit tab.';
    }
    await _softDelete('sales', saleId);
    _changed();
    return null;
  }

  Future<List<SaleRow>> sales(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery('''
SELECT s.*, p.name AS product_name, p.brand AS brand, p.model AS model
FROM sales s LEFT JOIN products p ON p.id = s.product_id
WHERE s.deleted = 0 AND s.sold_at >= ? AND s.sold_at < ?
ORDER BY s.sold_at DESC
''', [_iso(from), _iso(to)]);
    return rows.map(SaleRow.fromMap).toList();
  }

  String _iso(DateTime d) => d.toUtc().toIso8601String();

  // --------------------------------------------------------------- credit

  /// Gives goods on credit. This also records the sale (so stock goes down
  /// and the profit is counted) and, if [paidNow] > 0, the first payment.
  Future<String?> addCredit({
    required String customerName,
    required String phone,
    required String productId,
    required String productName,
    required int qty,
    required double totalDue,
    double extraCost = 0,
    double paidNow = 0,
    required String expectedDate,
    String note = '',
  }) async {
    if (customerName.trim().isEmpty) return 'Enter the customer name.';
    if (qty <= 0) return 'Quantity must be at least 1.';
    if (totalDue <= 0) return 'Enter the total amount due.';
    if (paidNow < 0 || paidNow > totalDue) {
      return 'The amount paid now must be between 0 and the total.';
    }
    final cost = await fifoUnitCost(productId, qty);
    if (cost == null) return 'Not enough stock for this item.';

    final creditBase = _base();
    final creditId = creditBase['id'] as String;
    final saleBase = _base();
    final saleId = saleBase['id'] as String;
    final now = _now();

    await _db.transaction((txn) async {
      await txn.insert('sales', {
        ...saleBase,
        'product_id': productId,
        'qty': qty,
        'unit_price': totalDue / qty,
        'unit_cost': cost,
        'extra_cost': extraCost,
        'customer': customerName.trim(),
        'note': note.trim(),
        'credit_id': creditId,
        'sold_at': now,
        'created_by': session.userId,
      });
      await txn.insert('credits', {
        ...creditBase,
        'sale_id': saleId,
        'product_id': productId,
        'product_name': productName,
        'customer_name': customerName.trim(),
        'phone': phone.trim(),
        'qty': qty,
        'total_due': totalDue,
        'taken_at': now,
        'expected_date': expectedDate,
        'note': note.trim(),
        'created_by': session.userId,
      });
      if (paidNow > 0) {
        await txn.insert('credit_payments', {
          ..._base(),
          'credit_id': creditId,
          'amount': paidNow,
          'paid_at': now,
          'created_by': session.userId,
        });
      }
    });
    _changed(credits: true);
    return null;
  }

  Future<List<CreditRow>> credits() async {
    final rows = await _db.rawQuery('''
SELECT c.*,
  COALESCE((SELECT SUM(p.amount) FROM credit_payments p WHERE p.credit_id = c.id AND p.deleted = 0), 0) AS paid
FROM credits c
WHERE c.deleted = 0
ORDER BY c.expected_date ASC, c.taken_at ASC
''');
    return rows.map(CreditRow.fromMap).toList();
  }

  Future<List<PaymentRow>> paymentsOf(String creditId) async {
    final rows = await _db.query('credit_payments',
        where: 'credit_id = ? AND deleted = 0',
        whereArgs: [creditId],
        orderBy: 'paid_at DESC');
    return rows.map(PaymentRow.fromMap).toList();
  }

  Future<String?> addPayment(String creditId, double amount) async {
    if (amount <= 0) return 'Enter an amount greater than zero.';
    final all = await credits();
    final match = all.where((c) => c.id == creditId);
    if (match.isEmpty) return 'Credit entry not found.';
    if (amount > match.first.balance + 0.004) {
      return 'That is more than the balance (${match.first.balance.toStringAsFixed(0)}).';
    }
    await _db.insert('credit_payments', {
      ..._base(),
      'credit_id': creditId,
      'amount': amount,
      'paid_at': _now(),
      'created_by': session.userId,
    });
    _changed(credits: true);
    return null;
  }

  Future<void> deletePayment(String paymentId) async {
    await _softDelete('credit_payments', paymentId);
    _changed(credits: true);
  }

  /// Deletes the credit entry together with its sale (stock returns).
  Future<void> deleteCredit(String creditId) async {
    final rows =
        await _db.query('credits', where: 'id = ?', whereArgs: [creditId]);
    if (rows.isEmpty) return;
    final saleId = strOf(rows.first['sale_id']);
    await _softDelete('credits', creditId);
    if (saleId.isNotEmpty) await _softDelete('sales', saleId);
    final pays = await _db.query('credit_payments',
        columns: ['id'], where: 'credit_id = ? AND deleted = 0', whereArgs: [creditId]);
    for (final p in pays) {
      await _softDelete('credit_payments', p['id'] as String);
    }
    _changed(credits: true);
  }

  Future<void> rescheduleReminders() async {
    try {
      await Reminders.instance.schedule(await credits());
    } catch (_) {}
  }

  // ------------------------------------------------------------ dashboard

  Future<PeriodSummary> summary(DateTime from, DateTime to) async {
    final a = _iso(from), b = _iso(to);
    final pur = await _db.rawQuery(
        'SELECT COALESCE(SUM(qty * unit_cost), 0) AS v FROM batches WHERE deleted = 0 AND purchased_at >= ? AND purchased_at < ?',
        [a, b]);
    final sal = await _db.rawQuery('''
SELECT
  COUNT(*) AS n,
  COALESCE(SUM(qty * unit_price), 0) AS revenue,
  COALESCE(SUM(qty * unit_cost), 0) AS cogs,
  COALESCE(SUM(extra_cost), 0) AS extra,
  COALESCE(SUM(CASE WHEN pr > 0 THEN pr ELSE 0 END), 0) AS profit,
  COALESCE(SUM(CASE WHEN pr < 0 THEN -pr ELSE 0 END), 0) AS loss
FROM (
  SELECT qty, unit_price, unit_cost, extra_cost,
    (qty * (unit_price - unit_cost) - extra_cost) AS pr
  FROM sales WHERE deleted = 0 AND sold_at >= ? AND sold_at < ?
)
''', [a, b]);
    final r = sal.first;
    return PeriodSummary(
      purchases: numOf(pur.first['v']),
      sales: numOf(r['revenue']),
      cogs: numOf(r['cogs']),
      extra: numOf(r['extra']),
      profit: numOf(r['profit']),
      loss: numOf(r['loss']),
      salesCount: intOf(r['n']),
    );
  }

  /// Money customers still owe, right now.
  Future<double> creditPending() async {
    final list = await credits();
    var total = 0.0;
    for (final c in list) {
      if (!c.isSettled) total += c.balance;
    }
    return total;
  }

  /// What the stock on the shelf cost you, right now.
  Future<double> stockValue() async {
    final list = await products();
    var total = 0.0;
    for (final p in list) {
      total += p.stockValue;
    }
    return total;
  }

  Future<List<BestSeller>> bestSellers(DateTime from, DateTime to,
      {int limit = 5}) async {
    final rows = await _db.rawQuery('''
SELECT p.name AS name, p.brand AS brand, p.model AS model,
  SUM(s.qty) AS q, SUM(s.qty * s.unit_price) AS revenue
FROM sales s JOIN products p ON p.id = s.product_id
WHERE s.deleted = 0 AND s.sold_at >= ? AND s.sold_at < ?
GROUP BY s.product_id
ORDER BY q DESC, revenue DESC
LIMIT ?
''', [_iso(from), _iso(to), limit]);
    return rows.map((r) {
      final bm = [strOf(r['brand']), strOf(r['model'])]
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
      final name = bm.isEmpty ? strOf(r['name']) : '${strOf(r['name'])} ($bm)';
      return BestSeller(name, intOf(r['q']), numOf(r['revenue']));
    }).toList();
  }

  /// The 12 months up to and including [lastMonth].
  Future<List<MonthRow>> lastTwelveMonths(DateTime lastMonth) async {
    final out = <MonthRow>[];
    for (var i = 11; i >= 0; i--) {
      final start = DateTime(lastMonth.year, lastMonth.month - i, 1);
      final end = DateTime(start.year, start.month + 1, 1);
      out.add(MonthRow(start, await summary(start, end)));
    }
    return out;
  }

  Future<List<Map<String, Object?>>> purchasesBetween(
      DateTime from, DateTime to) async {
    return _db.rawQuery('''
SELECT b.*, p.name AS product_name, p.brand AS brand, p.model AS model, p.category AS category
FROM batches b LEFT JOIN products p ON p.id = b.product_id
WHERE b.deleted = 0 AND b.purchased_at >= ? AND b.purchased_at < ?
ORDER BY b.purchased_at ASC
''', [_iso(from), _iso(to)]);
  }
}
