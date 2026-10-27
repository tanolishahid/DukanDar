import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../perms.dart';
import '../services/files.dart';
import '../services/reports.dart';
import '../services/repo.dart';
import '../services/session.dart';
import '../ui.dart';

class _DashData {
  _DashData(this.month, this.best, this.credit, this.stock, this.year);

  final Summary month;
  final List<BestSeller> best;
  final double credit;
  final double stock;
  final List<MonthRow> year;
}

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  DateTime get _next => DateTime(_month.year, _month.month + 1, 1);

  void _shift(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  Future<_DashData> _load(Repo repo) async {
    return _DashData(
      await repo.summary(_month, _next),
      await repo.bestSellers(_month, _next),
      await repo.creditPending(),
      await repo.stockValue(),
      await repo.lastTwelveMonths(_month),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final canExport = session.can(Perm.reports);

    return Scaffold(
      floatingActionButton: canExport
          ? FloatingActionButton.extended(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _ExportDialog(initialMonth: _month),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Download report'),
            )
          : null,
      body: RepoFuture<_DashData>(
        deps: [_month],
        load: _load,
        builder: (ctx, d) {
          final m = d.month;
          final net = m.net;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      onPressed: () => _shift(-1),
                      icon: const Icon(Icons.chevron_left)),
                  Text(fmtMonth(_month),
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                      onPressed: () => _shift(1),
                      icon: const Icon(Icons.chevron_right)),
                ],
              ),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width >= 700 ? 4 : 2,
                childAspectRatio: 2.2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  KpiTile(
                      label: 'Purchases',
                      value: rs(m.purchases),
                      icon: Icons.shopping_cart_outlined),
                  KpiTile(
                      label: 'Sales (${m.salesCount})',
                      value: rs(m.sales),
                      icon: Icons.point_of_sale),
                  KpiTile(
                      label: 'Profit',
                      value: rs(m.profit),
                      color: profitColor(context),
                      icon: Icons.trending_up),
                  KpiTile(
                      label: 'Loss',
                      value: rs(m.loss),
                      color: lossColor(context),
                      icon: Icons.trending_down),
                  KpiTile(
                      label: net >= 0 ? 'Net profit' : 'Net loss',
                      value: rs(net.abs()),
                      color: net >= 0 ? profitColor(context) : lossColor(context),
                      icon: Icons.balance),
                  KpiTile(
                      label: 'Extra costs',
                      value: rs(m.extra),
                      icon: Icons.local_shipping_outlined),
                  KpiTile(
                      label: 'Credit pending (now)',
                      value: rs(d.credit),
                      icon: Icons.account_balance_wallet_outlined),
                  KpiTile(
                      label: 'Stock value (now)',
                      value: rs(d.stock),
                      icon: Icons.inventory_2_outlined),
                ],
              ),
              const SizedBox(height: 20),
              Text('Best-selling products',
                  style: Theme.of(context).textTheme.titleMedium),
              if (d.best.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No sales this month.'),
                ),
              for (var i = 0; i < d.best.length; i++)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(d.best[i].name),
                  trailing: Text('${d.best[i].qty} sold  ·  ${rs(d.best[i].revenue)}'),
                ),
              const SizedBox(height: 20),
              Text('Last 12 months',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _YearTable(rows: d.year),
            ],
          );
        },
      ),
    );
  }
}

class _YearTable extends StatelessWidget {
  const _YearTable({required this.rows});

  final List<MonthRow> rows;

  @override
  Widget build(BuildContext context) {
    var maxSales = 0.0;
    for (final r in rows) {
      if (r.summary.sales > maxSales) maxSales = r.summary.sales;
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        headingRowHeight: 40,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 40,
        columns: const [
          DataColumn(label: Text('Month')),
          DataColumn(label: Text('Purchases'), numeric: true),
          DataColumn(label: Text('Sales'), numeric: true),
          DataColumn(label: Text('Profit'), numeric: true),
          DataColumn(label: Text('Loss'), numeric: true),
        ],
        rows: [
          for (final r in rows.reversed)
            DataRow(cells: [
              DataCell(Text(fmtMonthShort(r.month))),
              DataCell(Text(rs(r.summary.purchases))),
              DataCell(Text(rs(r.summary.sales))),
              DataCell(Text(rs(r.summary.profit),
                  style: TextStyle(color: profitColor(context)))),
              DataCell(Text(rs(r.summary.loss),
                  style: TextStyle(color: lossColor(context)))),
            ]),
        ],
      ),
    );
  }
}

enum _Preset { thisMonth, lastMonth, thisYear, custom }

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.initialMonth});

  final DateTime initialMonth;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  _Preset _preset = _Preset.thisMonth;
  DateTimeRange? _custom;
  bool _busy = false;

  (DateTime, DateTime)? _range() {
    final now = DateTime.now();
    switch (_preset) {
      case _Preset.thisMonth:
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1));
      case _Preset.lastMonth:
        return (DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 1));
      case _Preset.thisYear:
        return (DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1));
      case _Preset.custom:
        final c = _custom;
        if (c == null) return null;
        return (
          DateTime(c.start.year, c.start.month, c.start.day),
          DateTime(c.end.year, c.end.month, c.end.day + 1)
        );
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _custom,
    );
    if (r != null) setState(() => _custom = r);
  }

  Future<void> _export(bool pdf) async {
    final range = _range();
    if (range == null) {
      toast(context, 'Choose the dates first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = context.read<Repo>();
      final shop = context.read<SessionState>().shopName;
      final data = await ReportData.load(repo, shop, range.$1, range.$2);
      final bytes = pdf ? await Reports.pdf(data) : Reports.excel(data);
      final name =
          'DukanDar_report_${Reports.fileStamp()}.${pdf ? 'pdf' : 'xlsx'}';
      final path = await FileOut.save(name, bytes);
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'Report saved: $path');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Could not create the report: $e');
      }
    }
  }

  static String _label(_Preset p) {
    switch (p) {
      case _Preset.thisMonth:
        return 'This month';
      case _Preset.lastMonth:
        return 'Last month';
      case _Preset.thisYear:
        return 'This year (full-year summary)';
      case _Preset.custom:
        return 'Choose dates';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download report'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in _Preset.values)
              RadioListTile<_Preset>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: p,
                groupValue: _preset,
                title: Text(_label(p)),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _preset = v);
                  if (v == _Preset.custom) _pickCustom();
                },
              ),
            if (_preset == _Preset.custom)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: TextButton.icon(
                  onPressed: _pickCustom,
                  icon: const Icon(Icons.date_range),
                  label: Text(_custom == null
                      ? 'Pick dates'
                      : '${fmtDate(_custom!.start)} - ${fmtDate(_custom!.end)}'),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _export(false),
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Excel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _export(true),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('PDF'),
        ),
      ],
    );
  }
}
