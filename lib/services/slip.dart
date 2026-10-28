import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../format.dart';
import '../models.dart';

/// Paper the slip is printed on.
enum SlipPaper { roll58, roll80, a4 }

extension SlipPaperLabel on SlipPaper {
  String get label {
    switch (this) {
      case SlipPaper.roll58:
        return 'Small roll (58 mm)';
      case SlipPaper.roll80:
        return 'Roll (80 mm)';
      case SlipPaper.a4:
        return 'A4 paper';
    }
  }
}

/// Remembers which paper this computer / phone prints on.
class SlipSettings {
  static const String _key = 'slip_paper';

  static Future<SlipPaper> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final i = prefs.getInt(_key) ?? SlipPaper.roll80.index;
      if (i >= 0 && i < SlipPaper.values.length) return SlipPaper.values[i];
    } catch (_) {}
    return SlipPaper.roll80;
  }

  static Future<void> save(SlipPaper paper) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, paper.index);
    } catch (_) {}
  }
}

/// Builds, prints and shares the customer's slip (bill).
/// The slip never shows purchase prices, profit or repair costs.
class Slip {
  static Future<Uint8List> build(
    BillRow bill, {
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    required SlipPaper paper,
  }) async {
    final doc = pw.Document();
    final isRoll = paper != SlipPaper.a4;
    final base = paper == SlipPaper.roll58 ? 8.0 : (isRoll ? 9.5 : 12.0);

    PdfPageFormat format;
    switch (paper) {
      case SlipPaper.roll58:
        format = PdfPageFormat.roll57.copyWith(
            marginLeft: 3 * PdfPageFormat.mm,
            marginRight: 3 * PdfPageFormat.mm,
            marginTop: 4 * PdfPageFormat.mm,
            marginBottom: 6 * PdfPageFormat.mm);
        break;
      case SlipPaper.roll80:
        format = PdfPageFormat.roll80.copyWith(
            marginLeft: 4 * PdfPageFormat.mm,
            marginRight: 4 * PdfPageFormat.mm,
            marginTop: 5 * PdfPageFormat.mm,
            marginBottom: 8 * PdfPageFormat.mm);
        break;
      case SlipPaper.a4:
        format = PdfPageFormat.a4.copyWith(
            marginLeft: 36, marginRight: 36, marginTop: 36, marginBottom: 36);
        break;
    }

    pw.TextStyle st(double scale, {bool bold = false}) => pw.TextStyle(
          fontSize: base * scale,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        );

    pw.Widget line() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 4),
          height: 0.6,
          color: PdfColors.grey700,
        );

    pw.Widget kv(String k, String v, {bool bold = false, double scale = 1}) =>
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: st(scale, bold: bold)),
            pw.Text(v, style: st(scale, bold: bold)),
          ],
        );

    final header = <pw.Widget>[
      pw.Center(
          child: pw.Text(shopName,
              textAlign: pw.TextAlign.center, style: st(1.5, bold: true))),
      if (shopAddress.trim().isNotEmpty)
        pw.Center(
            child: pw.Text(shopAddress,
                textAlign: pw.TextAlign.center, style: st(0.95))),
      if (shopPhone.trim().isNotEmpty)
        pw.Center(
            child: pw.Text('Phone: $shopPhone',
                textAlign: pw.TextAlign.center, style: st(0.95))),
      line(),
      kv('Bill no', bill.billNo.isEmpty ? '-' : bill.billNo, scale: 0.95),
      kv('Date', fmtDateTime(bill.billedAt), scale: 0.95),
      if (bill.customer.trim().isNotEmpty)
        kv('Customer', bill.customer, scale: 0.95),
      if (bill.phone.trim().isNotEmpty) kv('Phone', bill.phone, scale: 0.95),
      line(),
    ];

    final items = <pw.Widget>[];
    for (final l in bill.lines) {
      final detail = [
        if (l.brandModel.isNotEmpty) l.brandModel,
      ].join(' ');
      items.add(pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(l.productName.isEmpty ? 'Item' : l.productName,
                style: st(1, bold: true)),
            if (detail.isNotEmpty) pw.Text(detail, style: st(0.9)),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('${l.qty} x ${rs(l.shownPrice)}', style: st(0.95)),
                pw.Text(rs(l.shownTotal), style: st(1)),
              ],
            ),
          ],
        ),
      ));
    }

    final totals = <pw.Widget>[
      line(),
      if (bill.discount > 0.004) ...[
        kv('Subtotal', rs(bill.subtotal)),
        kv('Discount', '- ${rs(bill.discount)}'),
      ],
      kv('TOTAL', rs(bill.total), bold: true, scale: 1.25),
      if (bill.hasBalance) ...[
        kv('Paid', rs(bill.paid)),
        kv('Balance due', rs(bill.balance), bold: true, scale: 1.1),
      ] else
        pw.Center(
            child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text('PAID IN FULL', style: st(1, bold: true)))),
      if (bill.note.trim().isNotEmpty && bill.note != 'Imported') ...[
        line(),
        pw.Text('Note: ${bill.note}', style: st(0.9)),
      ],
      line(),
      pw.Center(child: pw.Text('Thank you for your business!', style: st(1))),
    ];

    doc.addPage(pw.Page(
      pageFormat: format,
      build: (ctx) {
        final content = pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: [...header, ...items, ...totals],
        );
        if (isRoll) return content;
        // On A4 keep the slip a readable width in the middle of the page.
        return pw.Align(
          alignment: pw.Alignment.topCenter,
          child: pw.SizedBox(width: 380, child: content),
        );
      },
    ));
    return doc.save();
  }

  static Future<void> print(
    BillRow bill, {
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    required SlipPaper paper,
  }) async {
    final bytes = await build(bill,
        shopName: shopName,
        shopPhone: shopPhone,
        shopAddress: shopAddress,
        paper: paper);
    await Printing.layoutPdf(
      name: 'Bill ${bill.billNo}',
      onLayout: (_) async => bytes,
    );
  }

  static Future<void> share(
    BillRow bill, {
    required String shopName,
    required String shopPhone,
    required String shopAddress,
    required SlipPaper paper,
  }) async {
    final bytes = await build(bill,
        shopName: shopName,
        shopPhone: shopPhone,
        shopAddress: shopAddress,
        paper: paper);
    final no = bill.billNo.isEmpty ? 'sale' : bill.billNo;
    await Printing.sharePdf(bytes: bytes, filename: 'bill_$no.pdf');
  }
}
