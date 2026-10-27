import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../perms.dart';
import '../services/repo.dart';
import '../services/session.dart';
import '../ui.dart';
import 'add_stock_screen.dart';

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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final c in const ['', catLaptop, catAccessory])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.isEmpty ? 'All' : c),
                      selected: _cat == c,
                      onSelected: (_) => setState(() => _cat = c),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RepoFuture<List<ProductStock>>(
              deps: [_search.text, _cat],
              load: (repo) => repo.products(query: _search.text, category: _cat),
              builder: (ctx, list) {
                var units = 0;
                var value = 0.0;
                for (final p in list) {
                  units += p.stock;
                  value += p.stockValue;
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Text('${list.length} products  ·  $units units in stock'),
                          const Spacer(),
                          if (showCost)
                            Text('Stock value ${rs(value)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? const Center(
                              child: Text(
                                  'No products yet.\nTap "Add stock" to add your first one.',
                                  textAlign: TextAlign.center))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 90),
                              itemCount: list.length,
                              itemBuilder: (ctx, i) => _ProductCard(
                                product: list[i],
                                showCost: showCost,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                      builder: (_) =>
                                          ProductDetailScreen(product: list[i])),
                                ),
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
    final low = p.stock <= 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: onTap,
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          p.typeLabel,
          if (p.brandModel.isNotEmpty) p.brandModel,
          if (showCost) 'Last cost ${rs(p.lastCost)}',
        ].join('  ·  ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${p.stock}',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: low ? Colors.red.shade700 : null)),
            Text(low ? 'out of stock' : 'in stock',
                style: Theme.of(context).textTheme.labelSmall),
          ],
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
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
