import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../perms.dart';
import '../services/repo.dart';
import '../services/session.dart';
import '../theme.dart';
import '../ui.dart';

enum _Range { today, week, month, all }

class SalesTab extends StatefulWidget {
  const SalesTab({super.key});

  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> {
  _Range _range = _Range.today;

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
      case _Range.all:
        return (DateTime(2000), DateTime(2100));
    }
  }

  static String _label(_Range r) {
    switch (r) {
      case _Range.today:
        return 'Today';
      case _Range.week:
        return 'Last 7 days';
      case _Range.month:
        return 'This month';
      case _Range.all:
        return 'All time';
    }
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
          MaterialPageRoute<void>(builder: (_) => const NewSaleScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New sale'),
      ),
      body: RepoFuture<List<SaleRow>>(
        deps: [_range],
        load: (repo) => repo.sales(from, to),
        builder: (ctx, list) {
          var revenue = 0.0, profit = 0.0, loss = 0.0;
          for (final s in list) {
            revenue += s.revenue;
            if (s.profit >= 0) {
              profit += s.profit;
            } else {
              loss += -s.profit;
            }
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              HeroCard(
                label: 'Sales - ${_label(_range)}',
                value: rs(revenue),
                caption: '${list.length} sales',
                chips: showProfit
                    ? [
                        HeroChip(
                            label: 'Profit',
                            value: rs(profit),
                            dot: AppColors.green),
                        HeroChip(
                            label: 'Loss', value: rs(loss), dot: AppColors.coral),
                      ]
                    : const <Widget>[],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final r in _Range.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_label(r)),
                          selected: _range == r,
                          onSelected: (_) => setState(() => _range = r),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No sales in this period.')),
                ),
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SaleCard(
                      sale: s,
                      showProfit: showProfit,
                      canDelete: session.can(Perm.edit)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({
    required this.sale,
    required this.showProfit,
    required this.canDelete,
  });

  final SaleRow sale;
  final bool showProfit;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final s = sale;
    final scheme = Theme.of(context).colorScheme;
    final title = s.brandModel.isEmpty
        ? s.productName
        : '${s.productName} · ${s.brandModel}';
    final good = s.profit >= 0;
    final color = good ? profitColor(context) : lossColor(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onLongPress: canDelete && !s.isCredit
            ? () async {
                final ok = await confirmDialog(context, 'Delete this sale?',
                    'The stock will be returned to your inventory.');
                if (!ok) return;
                final err = await context.read<Repo>().deleteSale(s.id);
                if (err != null && context.mounted) toast(context, err);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                    showProfit
                        ? (good ? Icons.trending_up : Icons.trending_down)
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
                        '${s.qty} × ${rs(s.unitPrice)}',
                        if (s.extraCost > 0) 'extra ${rs(s.extraCost)}',
                        if (s.customer.isNotEmpty) s.customer,
                        if (s.isCredit) 'on credit',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurface.withValues(alpha: 0.65)),
                    ),
                    Text(fmtDateTime(s.soldAt),
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
                  Text(rs(s.revenue),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  if (showProfit)
                    Text(
                      good ? '+${rs(s.profit)}' : '-${rs(-s.profit)}',
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

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _extra = TextEditingController();
  final _customer = TextEditingController();

  ProductStock? _product;
  double? _unitCost; // purchase price of the units about to be sold
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    _extra.dispose();
    _customer.dispose();
    super.dispose();
  }

  int get _qtyValue => int.tryParse(_qty.text.trim()) ?? 0;

  Future<void> _pick() async {
    final p = await pickProduct(context);
    if (p == null) return;
    setState(() => _product = p);
    await _refreshCost();
  }

  Future<void> _refreshCost() async {
    final p = _product;
    if (p == null) return;
    final c = await context.read<Repo>().fifoUnitCost(p.id, _qtyValue);
    if (mounted) setState(() => _unitCost = c);
  }

  double? get _profit {
    final price = parseNum(_price.text);
    final cost = _unitCost;
    if (price == null || cost == null) return null;
    return _qtyValue * (price - cost) - (parseNum(_extra.text) ?? 0);
  }

  Future<void> _save() async {
    if (_product == null) {
      toast(context, 'Choose a product first.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final err = await context.read<Repo>().addSale(
          productId: _product!.id,
          qty: _qtyValue,
          unitPrice: parseNum(_price.text) ?? 0,
          extraCost: parseNum(_extra.text) ?? 0,
          customer: _customer.text,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      toast(context, err);
    } else {
      toast(context, 'Sale saved.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final showCost = session.can(Perm.viewCost);
    final p = _product;
    final profit = _profit;

    return Scaffold(
      appBar: AppBar(title: const Text('New sale')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.search),
                title: Text(p == null ? 'Choose product from inventory' : p.name),
                subtitle: p == null
                    ? null
                    : Text([
                        p.typeLabel,
                        if (p.brandModel.isNotEmpty) p.brandModel,
                        '${p.stock} in stock',
                      ].join('  ·  ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pick,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    onChanged: (_) {
                      setState(() {});
                      _refreshCost();
                    },
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 1) return 'At least 1';
                      if (p != null && n > p.stock) return 'Only ${p.stock} left';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Selling price (each)', prefixText: 'Rs '),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      final n = parseNum(v ?? '');
                      return (n == null || n < 0) ? 'Enter the price' : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _extra,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Extra costs (optional)',
                helperText: 'Delivery, repair... this reduces your profit',
                prefixText: 'Rs ',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _customer,
              decoration: const InputDecoration(labelText: 'Customer name (optional)'),
            ),
            const SizedBox(height: 16),
            if (showCost && profit != null && _unitCost != null)
              Card(
                color: (profit >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Purchase price: ${rs(_unitCost!)} each'),
                      const SizedBox(height: 4),
                      profitText(context, profit,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save sale'),
            ),
          ],
        ),
      ),
    );
  }
}
