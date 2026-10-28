import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../perms.dart';
import '../services/session.dart';
import '../theme.dart';
import '../ui.dart';
import 'bill_screens.dart';
import 'past_import_screen.dart';

enum _Range { today, week, month, year, all, custom }

class SalesTab extends StatefulWidget {
  const SalesTab({super.key});

  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  _Range _range = _Range.today;
  DateTimeRange? _custom;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  (DateTime, DateTime) _bounds() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    switch (_range) {
      case _Range.today:
        return (today, tomorrow);
      case _Range.week:
        return (DateTime(now.year, now.month, now.day - 6), tomorrow);
      case _Range.month:
        return (DateTime(now.year, now.month, 1), tomorrow);
      case _Range.year:
        return (DateTime(now.year, 1, 1), tomorrow);
      case _Range.all:
        return (DateTime(2000), DateTime(2100));
      case _Range.custom:
        final c = _custom;
        if (c == null) return (today, tomorrow);
        return (c.start, DateTime(c.end.year, c.end.month, c.end.day + 1));
    }
  }

  String _label(_Range r) {
    switch (r) {
      case _Range.today:
        return 'Today';
      case _Range.week:
        return 'Last 7 days';
      case _Range.month:
        return 'This month';
      case _Range.year:
        return 'This year';
      case _Range.all:
        return 'All time';
      case _Range.custom:
        final c = _custom;
        return c == null
            ? 'Pick dates'
            : '${fmtDate(c.start)} - ${fmtDate(c.end)}';
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _custom,
    );
    if (r != null) {
      setState(() {
        _custom = r;
        _range = _Range.custom;
      });
    }
  }

  bool _matches(BillRow b, String q) {
    if (q.isEmpty) return true;
    final hay =
        '${b.billNo} ${b.customer} ${b.phone} ${b.summary}'.toLowerCase();
    return hay.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final showProfit = session.can(Perm.viewCost);
    final (from, to) = _bounds();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const NewBillScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New bill'),
      ),
      body: RepoFuture<List<BillRow>>(
        deps: [_range, _custom?.start, _custom?.end],
        load: (repo) => repo.bills(from, to),
        builder: (ctx, all) {
          final q = _search.text.trim().toLowerCase();
          final list = all.where((b) => _matches(b, q)).toList();
          var revenue = 0.0, profit = 0.0, loss = 0.0;
          for (final b in list) {
            revenue += b.total;
            for (final l in b.lines) {
              if (l.profit >= 0) {
                profit += l.profit;
              } else {
                loss += -l.profit;
              }
            }
          }
          const pad = EdgeInsets.fromLTRB(16, 4, 16, 100);

          // 3 fixed rows (summary, filters, search) then one row per bill.
          return ListView.builder(
            padding: pad,
            itemCount: 3 + (list.isEmpty ? 1 : list.length),
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: HeroCard(
                    label: 'Sales - ${_label(_range)}',
                    value: rs(revenue),
                    caption:
                        '${list.length} ${list.length == 1 ? 'bill' : 'bills'}',
                    chips: showProfit
                        ? [
                            HeroChip(
                                label: 'Profit',
                                value: rs(profit),
                                dot: AppColors.green),
                            HeroChip(
                                label: 'Loss',
                                value: rs(loss),
                                dot: AppColors.coral),
                          ]
                        : const <Widget>[],
                  ),
                );
              }
              if (i == 1) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final r in _Range.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_label(r)),
                              selected: _range == r,
                              onSelected: (_) {
                                if (r == _Range.custom) {
                                  _pickRange();
                                } else {
                                  setState(() => _range = r);
                                }
                              },
                            ),
                          ),
                        if (session.can(Perm.addInventory))
                          ActionChip(
                            avatar: const Icon(Icons.history, size: 18),
                            label: const Text('Import past sales'),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => const PastImportScreen()),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
              if (i == 2) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search customer, bill no or item',
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                );
              }
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No bills in this period.')),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _BillCard(bill: list[i - 3], showProfit: showProfit),
              );
            },
          );
        },
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill, required this.showProfit});

  final BillRow bill;
  final bool showProfit;

  @override
  Widget build(BuildContext context) {
    final b = bill;
    final scheme = Theme.of(context).colorScheme;
    final profit = b.profit;
    final good = profit >= 0;
    final color = good ? profitColor(context) : lossColor(context);
    final title = b.summary.isEmpty ? 'Sale' : b.summary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => BillDetailScreen(bill: b)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (showProfit ? color : scheme.primary)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                    b.isRepairOnly
                        ? Icons.build_outlined
                        : Icons.receipt_long_outlined,
                    color: showProfit ? color : scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (b.billNo.isNotEmpty) b.billNo,
                        if (b.customer.isNotEmpty) b.customer,
                        if (b.lines.length > 1) '${b.lines.length} lines',
                        if (b.discount > 0.004) 'discount ${rs(b.discount)}',
                        if (b.hasBalance) 'owes ${rs(b.balance)}',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: b.hasBalance
                              ? warnColor(context)
                              : scheme.onSurface.withValues(alpha: 0.65)),
                    ),
                    Text(fmtDateTime(b.billedAt),
                        style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurface.withValues(alpha: 0.5))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(rs(b.total),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  if (showProfit)
                    Text(
                      good ? '+${rs(profit)}' : '-${rs(-profit)}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
