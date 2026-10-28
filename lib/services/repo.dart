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
  Future<double?> fifoUnitCost(String productId, int qty) =>
      _fifo(_db, productId, qty);

  Future<double?> _fifo(DatabaseExecutor db, String productId, int qty) async {
    if (qty <= 0) return null;
    final batches = await db.query('batches',
        where: 'product_id = ? AND deleted = 0',
        whereArgs: [productId],
        orderBy: 'purchased_at ASC');
    final soldRows = await db.rawQuery(
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


  // ---------------------------------------------------------------- bills

  String _billNo(DateTime d, String id) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'B${two(d.year % 100)}${two(d.month)}${two(d.day)}-'
        '${id.substring(0, 3).toUpperCase()}';
  }

  /// Saves one bill (slip) with any number of items and repair / service
  /// lines. Stock goes down per item (oldest purchase first), the discount is
  /// shared over the lines so profit stays right, and if the customer pays
  /// only part, one credit entry is created for the rest.
  ///
  /// [paidNow] null means "paid in full". [when] is only used when importing
  /// old data.
  Future<String?> addBill({
    required String customer,
    String phone = '',
    String note = '',
    required List<BillLineInput> lines,
    double discount = 0,
    double? paidNow,
    String expectedDate = '',
    DateTime? when,
  }) async {
    if (lines.isEmpty) return 'Add at least one item or service.';
    for (final l in lines) {
      if (l.qty <= 0) return 'Quantity must be at least 1.';
      if (l.price < 0) return 'A price cannot be negative.';
      if (l.productId.isEmpty && l.name.trim().isEmpty) {
        return 'Write a description for the repair / service line.';
      }
    }
    final subtotal = lines.fold(0.0, (a, l) => a + l.qty * l.price);
    if (discount < 0 || discount > subtotal + 0.004) {
      return 'The discount cannot be more than the bill total.';
    }
    final total = subtotal - discount;
    final paid = paidNow ?? total;
    if (paid < 0 || paid > total + 0.004) {
      return 'The amount received must be between 0 and the total.';
    }
    final balance = total - paid;
    if (balance > 0.004) {
      if (customer.trim().isEmpty) {
        return 'Enter the customer name when part of the bill is unpaid.';
      }
      if (expectedDate.isEmpty) {
        return 'Choose the date the customer will pay the rest.';
      }
    }

    final billBase = _base();
    final billId = billBase['id'] as String;
    final moment = when ?? DateTime.now();
    final at = moment.toUtc().toIso8601String();
    final billNo = _billNo(moment, billId);
    var creditId = '';

    try {
      await _db.transaction((txn) async {
        final names = <String>[];
        var qtyTotal = 0;
        for (final l in lines) {
          final lineSub = l.qty * l.price;
          final share = subtotal <= 0 ? 0.0 : discount * lineSub / subtotal;
          final effUnit = (lineSub - share) / l.qty;
          double unitCost = l.unitCost;
          if (l.productId.isNotEmpty) {
            final c = await _fifo(txn, l.productId, l.qty);
            if (c == null) throw _BillError('Not enough stock for ${l.name}.');
            unitCost = c;
          }
          await txn.insert('sales', {
            ..._base(),
            'product_id': l.productId,
            'qty': l.qty,
            'unit_price': effUnit,
            'unit_cost': unitCost,
            'extra_cost': l.extraCost,
            'customer': customer.trim(),
            'note': note.trim(),
            'credit_id': '',
            'sold_at': at,
            'created_by': session.userId,
            'bill_id': billId,
            'list_price': l.price,
            'item_name': l.productId.isEmpty ? l.name.trim() : '',
          });
          names.add(l.name.trim());
          qtyTotal += l.qty;
        }

        if (balance > 0.004) {
          final creditBase = _base();
          creditId = creditBase['id'] as String;
          var label = 'Bill $billNo: ${names.join(', ')}';
          if (label.length > 90) label = '${label.substring(0, 87)}...';
          await txn.insert('credits', {
            ...creditBase,
            'sale_id': '',
            'product_id': '',
            'product_name': label,
            'customer_name': customer.trim(),
            'phone': phone.trim(),
            'qty': qtyTotal,
            'total_due': total,
            'taken_at': at,
            'expected_date': expectedDate,
            'note': note.trim(),
            'created_by': session.userId,
          });
          if (paid > 0.004) {
            await txn.insert('credit_payments', {
              ..._base(),
              'credit_id': creditId,
              'amount': paid,
              'paid_at': at,
              'created_by': session.userId,
            });
          }
        }

        await txn.insert('bills', {
          ...billBase,
          'bill_no': billNo,
          'customer': customer.trim(),
          'phone': phone.trim(),
          'note': note.trim(),
          'discount': discount,
          'total': total,
          'credit_id': creditId,
          'billed_at': at,
          'created_by': session.userId,
        });
      });
    } on _BillError catch (e) {
      return e.message;
    }
    lastBillId = billId;
    _changed(credits: creditId.isNotEmpty);
    return null;
  }

  /// The bill saved most recently (so the screen can offer to print it).
  String lastBillId = '';

  /// Bills in a date range, newest first. Sales from before bills existed
  /// appear as one-line bills.
  Future<List<BillRow>> bills(DateTime from, DateTime to) async {
    final lines = await sales(from, to);
    final billRows = await _db.query('bills',
        where: 'deleted = 0 AND billed_at >= ? AND billed_at < ?',
        whereArgs: [_iso(from), _iso(to)]);
    final paidRows = await _db.rawQuery(
        'SELECT credit_id, SUM(amount) AS paid FROM credit_payments '
        'WHERE deleted = 0 GROUP BY credit_id');
    final paidBy = <String, double>{
      for (final r in paidRows) strOf(r['credit_id']): numOf(r['paid'])
    };

    final byBill = <String, List<SaleRow>>{};
    final out = <BillRow>[];
    for (final l in lines) {
      if (l.billId.isEmpty) {
        out.add(BillRow(
          id: l.id,
          billNo: '',
          customer: l.customer,
          phone: '',
          note: l.note,
          discount: 0,
          total: l.revenue,
          paid: l.isCredit ? (paidBy[l.creditId] ?? 0) : l.revenue,
          billedAt: l.soldAt,
          lines: [l],
          creditId: l.creditId,
          isLegacy: true,
        ));
      } else {
        byBill.putIfAbsent(l.billId, () => []).add(l);
      }
    }
    for (final b in billRows) {
      final id = strOf(b['id']);
      final billLines = byBill[id] ?? const <SaleRow>[];
      if (billLines.isEmpty) continue;
      final creditId = strOf(b['credit_id']);
      final total = numOf(b['total']);
      out.add(BillRow(
        id: id,
        billNo: strOf(b['bill_no']),
        customer: strOf(b['customer']),
        phone: strOf(b['phone']),
        note: strOf(b['note']),
        discount: numOf(b['discount']),
        total: total,
        paid: creditId.isEmpty ? total : (paidBy[creditId] ?? 0),
        billedAt: dateOf(b['billed_at']),
        lines: billLines,
        creditId: creditId,
        isLegacy: false,
      ));
    }
    out.sort((a, b) => b.billedAt.compareTo(a.billedAt));
    return out;
  }

  /// One bill by id. [near] is roughly when it was made (makes this fast).
  Future<BillRow?> billById(String id, {DateTime? near}) async {
    final centre = near ?? DateTime.now();
    final list = await bills(centre.subtract(const Duration(days: 1)),
        centre.add(const Duration(days: 1)));
    for (final b in list) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Deletes a whole bill: stock goes back and any credit entry is removed.
  Future<String?> deleteBill(BillRow bill) async {
    if (bill.isLegacy) {
      return deleteSale(bill.lines.first.id);
    }
    await _db.transaction((txn) async {
      Future<void> soft(String table, String where, List<Object?> args) =>
          txn.update(table,
              {'deleted': 1, 'updated_at': _now(), 'synced': 0},
              where: where, whereArgs: args);
      await soft('bills', 'id = ?', [bill.id]);
      await soft('sales', 'bill_id = ?', [bill.id]);
      if (bill.creditId.isNotEmpty) {
        await soft('credits', 'id = ?', [bill.creditId]);
        await soft('credit_payments', 'credit_id = ?', [bill.creditId]);
      }
    });
    _changed(credits: bill.creditId.isNotEmpty);
    return null;
  }

  /// Imports old bills from the "past sales" Excel file. Old items do not
  /// touch today's stock. Returns a short message and the skipped rows.
  Future<PastImportResult> importPastBills(List<PastBill> bills) async {
    var done = 0;
    final problems = <String>[];
    // One big transaction is much faster for thousands of bills.
    final stamp = _now();
    await _db.transaction((txn) async {
      for (final b in bills) {
        final subtotal = b.lines.fold(0.0, (a, l) => a + l.qty * l.price);
        if (subtotal <= 0) {
          problems.add('${b.label}: total is zero');
          continue;
        }
        final discount = b.discount.clamp(0, subtotal).toDouble();
        final total = subtotal - discount;
        final received = (b.received ?? total).clamp(0, total).toDouble();
        final balance = total - received;
        final billBase = _base();
        final billId = billBase['id'] as String;
        final at = b.date.toUtc().toIso8601String();
        var creditId = '';
        for (final l in b.lines) {
          final lineSub = l.qty * l.price;
          final share = discount * lineSub / subtotal;
          await txn.insert('sales', {
            ..._base(),
            'product_id': '',
            'qty': l.qty,
            'unit_price': (lineSub - share) / l.qty,
            'unit_cost': l.unitCost,
            'extra_cost': l.extraCost,
            'customer': b.customer,
            'note': 'Imported',
            'credit_id': '',
            'sold_at': at,
            'created_by': session.userId,
            'bill_id': billId,
            'list_price': l.price,
            'item_name': l.name,
          });
        }
        if (balance > 0.004) {
          final cb = _base();
          creditId = cb['id'] as String;
          var label = 'Bill ${b.billNo}: ${b.lines.map((l) => l.name).join(', ')}';
          if (label.length > 90) label = '${label.substring(0, 87)}...';
          await txn.insert('credits', {
            ...cb,
            'sale_id': '',
            'product_id': '',
            'product_name': label,
            'customer_name': b.customer.isEmpty ? 'Walk-in customer' : b.customer,
            'phone': b.phone,
            'qty': b.lines.fold(0, (a, l) => a + l.qty),
            'total_due': total,
            'taken_at': at,
            'expected_date': isoDayOf(b.date.add(const Duration(days: 30))),
            'note': 'Imported',
            'created_by': session.userId,
          });
          if (received > 0.004) {
            await txn.insert('credit_payments', {
              ..._base(),
              'credit_id': creditId,
              'amount': received,
              'paid_at': at,
              'created_by': session.userId,
            });
          }
        }
        await txn.insert('bills', {
          ...billBase,
          'bill_no': b.billNo.isEmpty ? _billNo(b.date, billId) : b.billNo,
          'customer': b.customer,
          'phone': b.phone,
          'note': 'Imported',
          'discount': discount,
          'total': total,
          'credit_id': creditId,
          'billed_at': at,
          'created_by': session.userId,
        });
        done++;
      }
    });
    if (stamp.isNotEmpty) _changed(credits: true);
    return PastImportResult(done, problems);
  }

  String isoDayOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    // A credit that belongs to a multi-item bill removes the whole bill.
    final billRows = await _db.query('bills',
        columns: ['id'], where: 'credit_id = ? AND deleted = 0', whereArgs: [creditId]);
    for (final b in billRows) {
      final billId = b['id'] as String;
      await _softDelete('bills', billId);
      await _db.update(
          'sales', {'deleted': 1, 'updated_at': _now(), 'synced': 0},
          where: 'bill_id = ?', whereArgs: [billId]);
    }
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

/// One line the cashier adds to a bill. [productId] is empty for a
/// repair / service line (no stock). [extraCost] is what that line cost you
/// (parts, labour, delivery) - it reduces profit but is not shown on the slip.
class BillLineInput {
  BillLineInput({
    this.productId = '',
    required this.name,
    this.qty = 1,
    required this.price,
    this.extraCost = 0,
    this.unitCost = 0,
  });

  final String productId;
  final String name;
  int qty;
  double price;
  double extraCost;

  /// Only for old imported lines; stock items use the purchase price.
  final double unitCost;

  bool get isService => productId.isEmpty;
}

class _BillError implements Exception {
  _BillError(this.message);
  final String message;
}

/// An old bill read from the "past sales" Excel file.
class PastBill {
  PastBill({
    required this.billNo,
    required this.date,
    required this.customer,
    required this.phone,
    required this.lines,
    this.discount = 0,
    this.received,
    required this.label,
  });

  final String billNo;
  final DateTime date;
  final String customer;
  final String phone;
  final List<BillLineInput> lines;
  final double discount;

  /// Null = paid in full.
  final double? received;

  /// For messages ("row 12").
  final String label;
}

class PastImportResult {
  PastImportResult(this.bills, this.problems);
  final int bills;
  final List<String> problems;
}
