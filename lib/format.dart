import 'package:intl/intl.dart';

final NumberFormat _rsFormat = NumberFormat('#,##0.##');

/// 12500 -> "Rs 12,500"
String rs(double v) => 'Rs ${_rsFormat.format(v)}';

String fmtDate(DateTime d) => DateFormat('dd MMM yyyy').format(d);

String fmtDateTime(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d);

String fmtMonth(DateTime d) => DateFormat('MMMM yyyy').format(d);

String fmtMonthShort(DateTime d) => DateFormat('MMM yy').format(d);

String isoDay(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Accepts "12,500" or "12500.5". Returns null if it is not a number.
double? parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim());
