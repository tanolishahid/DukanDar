import 'package:flutter/material.dart';

import '../responsive.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../perms.dart';
import '../services/repo.dart';
import '../services/session.dart';
import '../theme.dart';
import '../ui.dart';
import 'add_stock_screen.dart';
import 'import_screen.dart';

class InventoryTab extends StatefulWidget {
  const InventoryTab({super.key});

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  final TextEditingController _search = TextEditingController();
  String _cat = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _add({ProductStock? existing}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => AddStockScreen(existing: existing)),
    );
  }

  void _import() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final showCost = session.can(Perm.viewCost);

    return Scaffold(
      floatingActionButton: session.can(Perm.addInventory)
          ? FloatingActionButton.extended(
              onPressed: () => _add(),
              icon: const Icon(Icons.add),
              label: const Text('Add stock'),
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: RepoFuture<List<ProductStock>>(
              deps: [_search.text, _cat],
              load: (repo) => repo.products(query: _search.text, category: _cat),
              builder: (ctx, list) {
                var units = 0;
                var value = 0.0;
                var out = 0;
                for (final p in list) {
                  units += p.stock;
                  value += p.stockValue;
                  if (p.stock <= 0) out++;
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    HeroCard(
                      label: showCost ? 'Stock value' : 'Items in stock',
                      value: showCost ? rs(value) : '$units',
                      caption: showCost
                          ? 'What your stock cost you'
                          : 'Units on the shelf',
                      chips: [
                        HeroChip(label: 'Products', value: '${list.length}'),
                        if (showCost)
                          HeroChip(label: 'Units', value: '$units'),
                        HeroChip(
                            label: 'Out of stock',
                            value: '$out',
                            dot: out > 0 ? AppColors.coral : AppColors.green),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search name, brand, model or serial',
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(_search.clear),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final c in const ['', catLaptop, catComputer, catAccessory])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(c.isEmpty ? 'All' : c),
                                selected: _cat == c,
                                onSelected: (_) => setState(() => _cat = c),
                              ),
                            ),
                          if (session.can(Perm.addInventory))
                            ActionChip(
                              avatar: const Icon(Icons.upload_file, size: 18),
                              label: const Text('Import from file'),
                              onPressed: _import,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Column(
                          children: [
                            const Text(
                                'No products yet.\nTap "Add stock", or import your list from a file.',
                                textAlign: TextAlign.center),
                            if (session.can(Perm.addInventory)) ...[
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _import,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Import from Excel / CSV'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    for (final p in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ProductCard(
                          product: p,
                          showCost: showCost,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => ProductDetailScreen(product: p)),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.showCost,
    required this.onTap,
  });

  final ProductStock product;
  final bool showCost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final out = p.stock <= 0;
    final low = !out && p.stock <= 2;
    final color = out
        ? lossColor(context)
        : (low ? warnColor(context) : profitColor(context));
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CategoryAvatar(category: p.category, subcategory: p.subcategory),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      [
                        p.typeLabel,
                        if (p.brandModel.isNotEmpty) p.brandModel,
                        if (showCost) 'Cost ${rs(p.lastCost)}',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.65)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pill(out ? 'Out' : '${p.stock} left', color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});

  final ProductStock product;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final showCost = session.can(Perm.viewCost);
    final p = product;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (session.can(Perm.edit))
            IconButton(
              tooltip: 'Delete product',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirmDialog(context, 'Delete product?',
                    'Delete "${p.name}" from your inventory?');
                if (!ok) return;
                final err = await context.read<Repo>().deleteProduct(p.id);
                if (!context.mounted) return;
                if (err != null) {
                  toast(context, err);
                } else {
                  Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      floatingActionButton: session.can(Perm.addInventory)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => AddStockScreen(existing: p)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Buy more'),
            )
          : null,
      body: RepoFuture<List<BatchRow>>(
        load: (repo) => repo.batchesOf(p.id),
        builder: (ctx, batches) {
          return ListView(
            padding: Responsive.pad(context, Responsive.formWidth(context),
                const EdgeInsets.fromLTRB(16, 16, 16, 90)),
            children: [
              Text(p.typeLabel, style: Theme.of(context).textTheme.labelLarge),
              if (p.brandModel.isNotEmpty)
                Text(p.brandModel, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: KpiTile(
                        label: 'In stock',
                        value: '${p.stock}',
                        icon: Icons.inventory_2_outlined)),
                if (showCost) ...[
                  const SizedBox(width: 12),
                  Expanded(
                      child: KpiTile(
                          label: 'Stock value',
                          value: rs(p.stockValue),
                          icon: Icons.payments_outlined)),
                ],
              ]),
              const SizedBox(height: 20),
              Text('Purchases', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (batches.isEmpty) const Text('No purchases.'),
              for (final b in batches)
                Card(
                  child: ListTile(
                    title: Text(showCost
                        ? '${b.qty} × ${rs(b.unitCost)}'
                        : '${b.qty} units'),
                    subtitle: Text([
                      fmtDateTime(b.purchasedAt),
                      if (b.serial.isNotEmpty) 'Serial ${b.serial}',
                    ].join('  ·  ')),
                    trailing: session.can(Perm.edit)
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await confirmDialog(
                                  context,
                                  'Remove this purchase?',
                                  'It will be taken out of your stock.');
                              if (!ok) return;
                              final err =
                                  await context.read<Repo>().deleteBatch(b.id);
                              if (err != null && context.mounted) {
                                toast(context, err);
                              }
                            },
                          )
                        : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
