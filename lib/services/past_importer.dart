import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'importer.dart';
import 'repo.dart';

/// Columns of the "past sales" file.
class PastField {
  static const String date = 'date';
  static const String billNo = 'billNo';
  static const String customer = 'customer';
  static const String phone = 'phone';
  static const String item = 'item';
  static const String qty = 'qty';
  static const String price = 'price';
  static const String cost = 'cost';
  static const String discount = 'discount';
  static const String received = 'received';

  static const List<String> all = [
    date,
    billNo,
    customer,
    phone,
    item,
    qty,
    price,
    cost,
    discount,
    received,
  ];

  static const Map<String, String> labels = {
    date: 'Date *',
    billNo: 'Bill no (same on every row of one bill)',
    customer: 'Customer name',
    phone: 'Customer phone',
    item: 'Item / work done *',
    qty: 'Quantity',
    price: 'Selling price (each) *',
    cost: 'Cost price (each)',
    discount: 'Discount on the bill',
    received: 'Amount received for the bill',
  };

  static const Map<String, List<String>> synonyms = {
    date: ['date', 'sale date', 'bill date', 'invoice date', 'day'],
    billNo: [
      'bill no',
      'bill number',
      'bill',
      'invoice no',
      'invoice number',
      'invoice',
      'receipt no',
      'slip no'
    ],
    customer: ['customer name', 'customer', 'client', 'party', 'buyer'],
    phone: ['customer phone', 'phone', 'mobile', 'contact', 'cell'],
    item: [
      'item',
      'item name',
      'product name',
      'product',
      'description',
      'particulars',
      'work done'
    ],
    qty: ['quantity', 'qty', 'pcs', 'units'],
    price: [
      'selling price',
      'sale price',
      'sell price',
      'unit price',
      'price',
      'rate',
      'amount each'
    ],
    cost: ['cost price', 'purchase price', 'buying price', 'unit cost', 'cost'],
    discount: ['discount', 'disc', 'less'],
    received: [
      'amount received',
      'received',
      'amount paid',
      'paid',
      'payment',
      'cash received'
    ],
  };
}

class PastConvertResult {
  PastConvertResult(this.bills, this.problems, this.lineCount);

  final List<PastBill> bills;
  final List<String> problems;
  final int lineCount;

  double get total => bills.fold<double>(0.0, (a, b) {
        final sub = b.lines.fold<double>(0.0, (x, l) => x + l.qty * l.price);
        return a + sub - b.discount;
      });

  DateTime? get first => bills.isEmpty
      ? null
      : bills.map((b) => b.date).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime? get last => bills.isEmpty
      ? null
      : bills.map((b) => b.date).reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Reads an Excel / CSV file of old sales (years of history) and turns it
/// into bills. Old items do not change today's stock.
class PastImporter {
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static ParsedTable parse(String fileName, Uint8List bytes) =>
      Importer.parse(fileName, bytes);

  static Map<String, int> autoMap(List<String> headers) {
    final norm = headers.map(_norm).toList();
    final used = <int>{};
    final map = <String, int>{};
    for (final pass in [0, 1]) {
      for (final field in PastField.all) {
        if (map.containsKey(field)) continue;
        for (final syn in PastField.synonyms[field]!) {
          var found = -1;
          for (var i = 0; i < norm.length; i++) {
            if (used.contains(i) || norm[i].isEmpty) continue;
            if (field == PastField.price &&
                RegExp(r'cost|purchase|buy').hasMatch(norm[i])) {
              continue;
            }
            if (field == PastField.cost &&
                RegExp(r'sell|sale|retail').hasMatch(norm[i])) {
              continue;
            }
            if (pass == 1 && syn.length < 4) continue;
            final hit = pass == 0 ? norm[i] == syn : norm[i].contains(syn);
            if (hit) {
              found = i;
              break;
            }
          }
          if (found >= 0) {
            map[field] = found;
            used.add(found);
            break;
          }
        }
      }
    }
    return map;
  }

  static const Map<String, int> _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Understands 2024-03-15, 15/03/2024, 15-03-24, 15 Mar 2024 and Excel
  /// date numbers. Day first for slashes (dd/mm/yyyy).
  static DateTime? parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    DateTime? make(int y, int m, int d) {
      if (y < 1990 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) {
        return null;
      }
      final dt = DateTime(y, m, d, 12);
      return dt.month == m ? dt : null;
    }

    var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
    if (m != null) {
      return make(int.parse(m.group(1)!), int.parse(m.group(2)!),
          int.parse(m.group(3)!));
    }
    m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})').firstMatch(s);
    if (m != null) {
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      return make(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
    }
    m = RegExp(r'^(\d{1,2})[\s\-]+([A-Za-z]{3,9})[\s\-,]+(\d{2,4})')
        .firstMatch(s);
    if (m != null) {
      final mon = _months[m.group(2)!.toLowerCase().substring(0, 3)];
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (mon != null) return make(y, mon, int.parse(m.group(1)!));
    }
    final serial = double.tryParse(s);
    if (serial != null && serial > 20000 && serial < 80000) {
      final d = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
      return make(d.year, d.month, d.day);
    }
    return null;
  }

  static double? _num(String s) {
    final t = s.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '').trim();
    return double.tryParse(t);
  }

  static PastConvertResult convert(ParsedTable table, Map<String, int> map) {
    final problems = <String>[];
    String cell(List<String> row, String field) {
      final i = map[field];
      if (i == null || i < 0 || i >= row.length) return '';
      return row[i].trim();
    }

    final order = <String>[];
    final groups = <String, _Group>{};
    var lineCount = 0;

    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      final line = r + 2;
      final item = cell(row, PastField.item);
      if (item.isEmpty) {
        problems.add('Row $line: no item');
        continue;
      }
      final date = parseDate(cell(row, PastField.date));
      if (date == null) {
        problems.add('Row $line: date not understood "${cell(row, PastField.date)}"');
        continue;
      }
      final price = _num(cell(row, PastField.price));
      if (price == null || price < 0) {
        problems.add('Row $line: no selling price');
        continue;
      }
      var qty = int.tryParse(cell(row, PastField.qty).replaceAll(',', '')) ?? 1;
      if (qty < 1) qty = 1;
      final cost = _num(cell(row, PastField.cost)) ?? 0;
      final billNo = cell(row, PastField.billNo);
      final key = billNo.isEmpty ? '#row$line' : 'no:$billNo';

      final g = groups.putIfAbsent(key, () {
        order.add(key);
        return _Group(billNo, date, 'row $line');
      });
      g.customer = g.customer.isEmpty ? cell(row, PastField.customer) : g.customer;
      g.phone = g.phone.isEmpty ? cell(row, PastField.phone) : g.phone;
      g.discount ??= _num(cell(row, PastField.discount));
      g.received ??= _num(cell(row, PastField.received));
      g.lines.add(BillLineInput(
          name: item, qty: qty, price: price, unitCost: cost));
      lineCount++;
    }

    final bills = <PastBill>[];
    for (final key in order) {
      final g = groups[key]!;
      bills.add(PastBill(
        billNo: g.billNo,
        date: g.date,
        customer: g.customer,
        phone: g.phone,
        lines: g.lines,
        discount: g.discount ?? 0,
        received: g.received,
        label: g.label,
      ));
    }
    return PastConvertResult(bills, problems, lineCount);
  }

  /// A sample file the shop can fill in.
  static List<int> template() {
    final book = Excel.createExcel();
    final first = book.getDefaultSheet();
    final sheet = book['Past sales'];
    sheet.appendRow([
      for (final h in const [
        'Date',
        'Bill no',
        'Customer',
        'Phone',
        'Item',
        'Qty',
        'Selling price',
        'Cost price',
        'Discount',
        'Amount received'
      ])
        TextCellValue(h)
    ]);
    List<CellValue> row(List<Object> v) => [
          for (final x in v)
            x is int
                ? IntCellValue(x)
                : TextCellValue(x.toString()),
        ];
    sheet.appendRow(row(['2023-03-15', 'A-101', 'Ali Raza', '03001234567',
        'HP ProBook 450 G8', 1, 78000, 65000, 1000, 77000]));
    sheet.appendRow(row(['2023-03-15', 'A-101', 'Ali Raza', '',
        'Wireless Mouse', 1, 1200, 900, '', '']));
    sheet.appendRow(row(['2023-03-16', 'A-102', '', '',
        'Laptop screen repair', 1, 6500, 4000, '', '']));
    if (first != null && first != 'Past sales') book.delete(first);
    book.setDefaultSheet('Past sales');
    return book.encode() ?? <int>[];
  }
}

class _Group {
  _Group(this.billNo, this.date, this.label);

  final String billNo;
  final DateTime date;
  final String label;
  String customer = '';
  String phone = '';
  double? discount;
  double? received;
  final List<BillLineInput> lines = [];
}
