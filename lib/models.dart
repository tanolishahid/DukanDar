double numOf(Object? v) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

int intOf(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

String strOf(Object? v) => v == null ? '' : v.toString();

DateTime dateOf(Object? v) =>
    DateTime.tryParse(strOf(v))?.toLocal() ?? DateTime.now();

const String catLaptop = 'Laptop';
const String catComputer = 'Computer';
const String catAccessory = 'Accessory';

/// Desktop-side machines sold in the Computer section.
const List<String> computerTypes = [
  'Desktop PC',
  'Gaming PC',
  'All-in-One',
  'Mini PC',
  'Workstation',
  'Server',
  'Other',
];

const List<String> accessoryTypes = [
  'Keyboard',
  'Mouse',
  'Charger',
  'Headphones',
  'Bag',
  'Battery',
  'RAM / SSD',
  'LCD',
  'LED',
  'Graphic card',
  'Processor',
  'Motherboard',
  'Power supply',
  'Casing',
  'Cooler / Fan',
  'HDD',
  'Printer',
  'Webcam',
  'Speaker',
  'UPS',
  'Router / Network',
  'Cable / Adapter',
  'Other',
];

/// Categories shown in the app, in order.
const List<String> allCategories = [catLaptop, catComputer, catAccessory];

/// The sub-types a category offers (empty for Laptop).
List<String> typesFor(String category) {
  if (category == catComputer) return computerTypes;
  if (category == catAccessory) return accessoryTypes;
  return const [];
}

class ProductStock {
  ProductStock({
    required this.id,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.brand,
    required this.model,
    required this.bought,
    required this.sold,
    required this.boughtValue,
    required this.soldCost,
    required this.lastCost,
  });

  final String id;
  final String name;
  final String category;
  final String subcategory;
  final String brand;
  final String model;
  final int bought;
  final int sold;
  final double boughtValue;
  final double soldCost;
  final double lastCost;

  int get stock => bought - sold;

  /// Money tied up in the units still on the shelf (first-in first-out).
  double get stockValue => boughtValue - soldCost;

  String get brandModel =>
      [brand, model].where((s) => s.trim().isNotEmpty).join(' ');

  String get typeLabel => category != catLaptop && subcategory.isNotEmpty
      ? subcategory
      : category;

  factory ProductStock.fromMap(Map<String, Object?> m) => ProductStock(
        id: strOf(m['id']),
        name: strOf(m['name']),
        category: strOf(m['category']),
        subcategory: strOf(m['subcategory']),
        brand: strOf(m['brand']),
        model: strOf(m['model']),
        bought: intOf(m['bought']),
        sold: intOf(m['sold']),
        boughtValue: numOf(m['bought_value']),
        soldCost: numOf(m['sold_cost']),
        lastCost: numOf(m['last_cost']),
      );
}

class BatchRow {
  BatchRow({
    required this.id,
    required this.qty,
    required this.unitCost,
    required this.serial,
    required this.purchasedAt,
  });

  final String id;
  final int qty;
  final double unitCost;
  final String serial;
  final DateTime purchasedAt;

  factory BatchRow.fromMap(Map<String, Object?> m) => BatchRow(
        id: strOf(m['id']),
        qty: intOf(m['qty']),
        unitCost: numOf(m['unit_cost']),
        serial: strOf(m['serial']),
        purchasedAt: dateOf(m['purchased_at']),
      );
}

class SaleRow {
  SaleRow({
    required this.id,
    required this.productId,
    required this.productName,
    required this.brandModel,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.extraCost,
    required this.customer,
    required this.note,
    required this.creditId,
    required this.soldAt,
    this.billId = '',
    this.listPrice,
  });

  final String id;
  final String billId;

  /// Price shown on the bill before the bill discount. Null on old sales.
  final double? listPrice;
  final String productId;
  final String productName;
  final String brandModel;
  final int qty;
  final double unitPrice;
  final double unitCost;
  final double extraCost;
  final String customer;
  final String note;
  final String creditId;
  final DateTime soldAt;

  double get revenue => qty * unitPrice;
  double get cost => qty * unitCost;
  double get profit => revenue - cost - extraCost;
  bool get isCredit => creditId.isNotEmpty;

  /// What the bill shows for this line (before the bill discount).
  double get shownPrice => listPrice ?? unitPrice;
  double get shownTotal => qty * shownPrice;

  /// A repair / service line has no product in stock.
  bool get isService => productId.isEmpty;

  factory SaleRow.fromMap(Map<String, Object?> m) => SaleRow(
        id: strOf(m['id']),
        billId: strOf(m['bill_id']),
        listPrice: m['list_price'] == null ? null : numOf(m['list_price']),
        productId: strOf(m['product_id']),
        productName: strOf(m['product_name']).isNotEmpty
            ? strOf(m['product_name'])
            : strOf(m['item_name']),
        brandModel: [strOf(m['brand']), strOf(m['model'])]
            .where((s) => s.trim().isNotEmpty)
            .join(' '),
        qty: intOf(m['qty']),
        unitPrice: numOf(m['unit_price']),
        unitCost: numOf(m['unit_cost']),
        extraCost: numOf(m['extra_cost']),
        customer: strOf(m['customer']),
        note: strOf(m['note']),
        creditId: strOf(m['credit_id']),
        soldAt: dateOf(m['sold_at']),
      );
}

/// One bill (slip): many lines, a discount, and what has been paid.
/// Sales made before bills existed appear as a bill with a single line.
class BillRow {
  BillRow({
    required this.id,
    required this.billNo,
    required this.customer,
    required this.phone,
    required this.note,
    required this.discount,
    required this.total,
    required this.paid,
    required this.billedAt,
    required this.lines,
    required this.creditId,
    required this.isLegacy,
  });

  final String id;
  final String billNo;
  final String customer;
  final String phone;
  final String note;
  final double discount;

  /// Amount to pay, after the discount.
  final double total;
  final double paid;
  final DateTime billedAt;
  final List<SaleRow> lines;
  final String creditId;
  final bool isLegacy;

  double get balance => total - paid;
  bool get hasBalance => balance > 0.004;
  double get subtotal => lines.fold(0.0, (a, l) => a + l.shownTotal);
  double get profit => lines.fold(0.0, (a, l) => a + l.profit);
  int get itemCount => lines.fold(0, (a, l) => a + l.qty);
  bool get isRepairOnly => lines.isNotEmpty && lines.every((l) => l.isService);

  /// "Laptop, Mouse, Repair" for lists.
  String get summary {
    final names = lines.map((l) => l.productName).where((n) => n.isNotEmpty);
    return names.join(', ');
  }
}

class CreditRow {
  CreditRow({
    required this.id,
    required this.saleId,
    required this.productName,
    required this.customerName,
    required this.phone,
    required this.qty,
    required this.totalDue,
    required this.paid,
    required this.takenAt,
    required this.expectedDate,
    required this.note,
  });

  final String id;
  final String saleId;
  final String productName;
  final String customerName;
  final String phone;
  final int qty;
  final double totalDue;
  final double paid;
  final DateTime takenAt;

  /// yyyy-MM-dd
  final String expectedDate;
  final String note;

  double get balance => totalDue - paid;
  bool get isSettled => balance <= 0.004;

  DateTime get expected => DateTime.tryParse(expectedDate) ?? takenAt;

  static String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  bool get isDueToday => !isSettled && expectedDate == _today();
  bool get isOverdue => !isSettled && expectedDate.compareTo(_today()) < 0;

  factory CreditRow.fromMap(Map<String, Object?> m) => CreditRow(
        id: strOf(m['id']),
        saleId: strOf(m['sale_id']),
        productName: strOf(m['product_name']),
        customerName: strOf(m['customer_name']),
        phone: strOf(m['phone']),
        qty: intOf(m['qty']),
        totalDue: numOf(m['total_due']),
        paid: numOf(m['paid']),
        takenAt: dateOf(m['taken_at']),
        expectedDate: strOf(m['expected_date']),
        note: strOf(m['note']),
      );
}

class PaymentRow {
  PaymentRow({required this.id, required this.amount, required this.paidAt});

  final String id;
  final double amount;
  final DateTime paidAt;

  factory PaymentRow.fromMap(Map<String, Object?> m) => PaymentRow(
        id: strOf(m['id']),
        amount: numOf(m['amount']),
        paidAt: dateOf(m['paid_at']),
      );
}

class PeriodSummary {
  PeriodSummary({
    this.purchases = 0,
    this.sales = 0,
    this.cogs = 0,
    this.extra = 0,
    this.profit = 0,
    this.loss = 0,
    this.salesCount = 0,
  });

  final double purchases;
  final double sales;
  final double cogs;
  final double extra;

  /// Sum of the sales that made money.
  final double profit;

  /// Sum (as a positive number) of the sales that lost money.
  final double loss;
  final int salesCount;

  double get net => profit - loss;
}

class MonthRow {
  MonthRow(this.month, this.summary);

  final DateTime month;
  final PeriodSummary summary;
}

class BestSeller {
  BestSeller(this.name, this.qty, this.revenue);

  final String name;
  final int qty;
  final double revenue;
}
