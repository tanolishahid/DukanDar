import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'format.dart';
import 'models.dart';
import 'perms.dart';
import 'services/repo.dart';
import 'services/session.dart';

export 'format.dart';

Color profitColor(BuildContext context) => Colors.green.shade700;
Color lossColor(BuildContext context) => Colors.red.shade700;

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
    BuildContext context, String title, String body) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes')),
      ],
    ),
  );
  return ok ?? false;
}

/// "+ Rs 500" in green or "- Rs 500" in red.
Widget profitText(BuildContext context, double v, {TextStyle? style}) {
  final good = v >= 0;
  final color = good ? profitColor(context) : lossColor(context);
  final label = good ? 'Profit ${rs(v)}' : 'Loss ${rs(-v)}';
  return Text(label,
      style: (style ?? const TextStyle(fontWeight: FontWeight.w600))
          .copyWith(color: color));
}

class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color ?? scheme.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.labelMedium,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads data from the Repo and reloads when data changes
/// (a local save, or something arriving from the cloud).
class RepoFuture<T> extends StatefulWidget {
  const RepoFuture({
    super.key,
    required this.load,
    required this.builder,
    this.deps = const [],
  });

  final Future<T> Function(Repo repo) load;
  final Widget Function(BuildContext context, T data) builder;

  /// Change one of these (search text, filter...) to force a reload.
  final List<Object?> deps;

  @override
  State<RepoFuture<T>> createState() => _RepoFutureState<T>();
}

class _RepoFutureState<T> extends State<RepoFuture<T>> {
  Future<T>? _future;
  int _version = -1;
  List<Object?> _deps = const [];

  bool _sameDeps() {
    if (_deps.length != widget.deps.length) return false;
    for (var i = 0; i < _deps.length; i++) {
      if (_deps[i] != widget.deps[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repo>();
    if (_future == null || _version != repo.version || !_sameDeps()) {
      _version = repo.version;
      _deps = List<Object?>.of(widget.deps);
      _future = widget.load(repo);
    }
    return FutureBuilder<T>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.hasData) return widget.builder(ctx, snap.data as T);
        if (snap.hasError) {
          return Center(child: Text('Something went wrong: ${snap.error}'));
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

Future<ProductStock?> pickProduct(BuildContext context,
    {bool inStockOnly = true}) {
  return showModalBottomSheet<ProductStock>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ProductPicker(inStockOnly: inStockOnly),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.inStockOnly});

  final bool inStockOnly;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final showCost = session.can(Perm.viewCost);
    final height = MediaQuery.of(context).size.height * 0.8;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name, brand, model or serial',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: RepoFuture<List<ProductStock>>(
                deps: [_search.text],
                load: (repo) => repo.products(
                    query: _search.text, inStockOnly: widget.inStockOnly),
                builder: (ctx, list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Text(widget.inStockOnly
                          ? 'No products in stock match.'
                          : 'No products match.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final p = list[i];
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text([
                          p.typeLabel,
                          if (p.brandModel.isNotEmpty) p.brandModel,
                          if (showCost) 'Cost ${rs(p.lastCost)}',
                        ].join('  ·  ')),
                        trailing: Text('${p.stock} in stock',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: p.stock <= 0
                                    ? Colors.red.shade700
                                    : null)),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
