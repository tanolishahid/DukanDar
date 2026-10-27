import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../format.dart';
import '../models.dart';
import 'repo.dart';

/// Everything a report needs, for any date range [from, to).
class ReportData {
  ReportData({
    required this.shopName,
    required this.from,
    required this.to,
    required this.summary,
    required this.sales,
    required this.purchases,
    required this.credits,
    required this.creditPending,
    required this.stockValue,
    required this.best,
  });

  final String shopName;
  final DateTime from;

  /// Exclusive end.
  final DateTime to;
  final Summary summary;
  final List<SaleRow> sales;
  final List<Map<String, Object?>> purchases;
  final List<CreditRow> credits;
  final double creditPending;
  final double stockValue;
  final List<BestSeller> best;

  String get rangeLabel {
    final last = to.subtract(const Duration(days: 1));
    return '${fmtDate(from)} to ${fmtDate(last)}';
  }

  static Future<ReportData> load(
      Repo repo, String shopName, DateTime from, DateTime to) async {
    final allCredits = await repo.credits();
    return ReportData(
      shopName: shopName,
      from: from,
      to: to,
      summary: await repo.summary(from, to),
      sales: await repo.sales(from, to),
      purchases: await repo.purchasesBetween(from, to),
      credits: allCredits.where((c) => !c.isSettled).toList(),
      creditPending: await repo.creditPending(),
      stockValue: await repo.stockValue(),
      best: await repo.bestSellers(from, to, limit: 10),
    );
  }
}

String _purchaseName(Map<String, Object?> r) {
  final bm = [strOf(r['brand']), strOf(r['model'])]
      .where((s) => s.trim().isNotEmpty)
      .join(' ');
  final name = strOf(r['product_name']);
  return bm.isEmpty ? name : '$name ($bm)';
}

String _saleName(SaleRow s) =>
    s.brandModel.isEmpty ? s.productName : '${s.productName} (${s.brandModel})';

class Reports {
  static String fileStamp() => DateFormat('yyyyMMdd').format(DateTime.now());

  // ---------------------------------------------------------------- Excel

  static List<int> excel(ReportData d) {
    final book = Excel.createExcel();
    final first = book.getDefaultSheet();

    void row(Sheet sheet, List<Object?> values) {
      sheet.appendRow(values.map<CellValue?>((v) {
        if (v == null) return null;
        if (v is int) return IntCellValue(v);
        if (v is double) return DoubleCellValue(double.parse(v.toStringAsFixed(2)));
        return TextCellValue(v.toString());
      }).toList());
    }

    // Summary
    final sum = book['Summary'];
    row(sum, [d.shopName]);
    row(sum, ['Report period', d.rangeLabel]);
    row(sum, []);
    row(sum, ['Total purchases (Rs)', d.summary.purchases]);
    row(sum, ['Total sales (Rs)', d.summary.sales]);
    row(sum, ['Profit from sales that made money (Rs)', d.summary.profit]);
    row(sum, ['Loss from sales below cost (Rs)', d.summary.loss]);
    row(sum, ['Net profit / loss (Rs)', d.summary.net]);
    row(sum, ['Extra costs - delivery, repair (Rs)', d.summary.extra]);
    row(sum, ['Number of sales', d.summary.salesCount]);
    row(sum, ['Credit pending today (Rs)', d.creditPending]);
    row(sum, ['Stock value today (Rs)', d.stockValue]);
    row(sum, []);
    row(sum, ['Best selling products']);
    row(sum, ['Product', 'Units sold', 'Sales (Rs)']);
    for (final b in d.best) {
      row(sum, [b.name, b.qty, b.revenue]);
    }

    // Sales
    final sales = book['Sales'];
    row(sales, [
      'Date',
      'Product',
      'Qty',
      'Purchase price each',
      'Selling price each',
      'Extra costs',
      'Profit / Loss',
      'Customer',
      'On credit'
    ]);
    for (final s in d.sales) {
      row(sales, [
        fmtDateTime(s.soldAt),
        _saleName(s),
        s.qty,
        s.unitCost,
        s.unitPrice,
        s.extraCost,
        s.profit,
        s.customer,
        s.isCredit ? 'Yes' : '',
      ]);
    }

    // Purchases
    final pur = book['Purchases'];
    row(pur, ['Date', 'Product', 'Category', 'Qty', 'Purchase price each', 'Total', 'Serial']);
    for (final r in d.purchases) {
      final q = intOf(r['qty']);
      final c = numOf(r['unit_cost']);
      row(pur, [
        fmtDateTime(dateOf(r['purchased_at'])),
        _purchaseName(r),
        strOf(r['category']),
        q,
        c,
        q * c,
        strOf(r['serial']),
      ]);
    }

    // Credit
    final cr = book['Credit'];
    row(cr, ['Customer', 'Phone', 'Product', 'Total due', 'Paid', 'Balance', 'Date taken', 'Expected date']);
    for (final c in d.credits) {
      row(cr, [
        c.customerName,
        c.phone,
        c.productName,
        c.totalDue,
        c.paid,
        c.balance,
        fmtDate(c.takenAt),
        c.expectedDate,
      ]);
    }

    if (first != null && first != 'Summary') {
      book.delete(first);
    }
    book.setDefaultSheet('Summary');
    return book.encode() ?? <int>[];
  }

  // ------------------------------------------------------------------ PDF

  static Future<List<int>> pdf(ReportData d) async {
    final doc = pw.Document();
    final head = pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13);

    pw.Widget table(List<String> headers, List<List<String>> data) {
      return pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
        cellPadding: const pw.EdgeInsets.all(3),
      );
    }

    String m(double v) => rs(v);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Text(d.shopName,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('Report: ${d.rangeLabel}'),
          pw.SizedBox(height: 12),
          table(['Item', 'Amount'], [
            ['Total purchases', m(d.summary.purchases)],
            ['Total sales', m(d.summary.sales)],
            ['Profit (sales that made money)', m(d.summary.profit)],
            ['Loss (sales below cost)', m(d.summary.loss)],
            ['Net profit / loss', m(d.summary.net)],
            ['Extra costs (delivery, repair)', m(d.summary.extra)],
            ['Number of sales', '${d.summary.salesCount}'],
            ['Credit pending today', m(d.creditPending)],
            ['Stock value today', m(d.stockValue)],
          ]),
          if (d.best.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('Best selling products', style: head),
            pw.SizedBox(height: 4),
            table(['Product', 'Units', 'Sales'],
                [for (final b in d.best) [b.name, '${b.qty}', m(b.revenue)]]),
          ],
          pw.SizedBox(height: 14),
          pw.Text('Sales', style: head),
          pw.SizedBox(height: 4),
          if (d.sales.isEmpty)
            pw.Text('No sales in this period.')
          else
            table(
              ['Date', 'Product', 'Qty', 'Cost', 'Price', 'Extra', 'Profit / Loss'],
              [
                for (final s in d.sales)
                  [
                    fmtDate(s.soldAt),
                    _saleName(s),
                    '${s.qty}',
                    m(s.unitCost),
                    m(s.unitPrice),
                    m(s.extraCost),
                    m(s.profit),
                  ]
              ],
            ),
          pw.SizedBox(height: 14),
          pw.Text('Purchases', style: head),
          pw.SizedBox(height: 4),
          if (d.purchases.isEmpty)
            pw.Text('No purchases in this period.')
          else
            table(
              ['Date', 'Product', 'Qty', 'Price each', 'Total'],
              [
                for (final r in d.purchases)
                  [
                    fmtDate(dateOf(r['purchased_at'])),
                    _purchaseName(r),
                    '${intOf(r['qty'])}',
                    m(numOf(r['unit_cost'])),
                    m(intOf(r['qty']) * numOf(r['unit_cost'])),
                  ]
              ],
            ),
          pw.SizedBox(height: 14),
          pw.Text('Credit still to be collected', style: head),
          pw.SizedBox(height: 4),
          if (d.credits.isEmpty)
            pw.Text('No pending credit.')
          else
            table(
              ['Customer', 'Phone', 'Product', 'Total', 'Paid', 'Balance', 'Due on'],
              [
                for (final c in d.credits)
                  [
                    c.customerName,
                    c.phone,
                    c.productName,
                    m(c.totalDue),
                    m(c.paid),
                    m(c.balance),
                    c.expectedDate,
                  ]
              ],
            ),
        ],
      ),
    );
    return doc.save();
  }
}
