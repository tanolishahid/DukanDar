import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'format.dart';
import 'models.dart';
import 'perms.dart';
import 'services/repo.dart';
import 'services/session.dart';
import 'theme.dart';

export 'format.dart';

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color profitColor(BuildContext context) =>
    _isDark(context) ? const Color(0xFF4ADE9F) : const Color(0xFF16966A);

Color lossColor(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFF8A73) : const Color(0xFFE5482D);

Color warnColor(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFFC857) : const Color(0xFFC77700);

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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

/// "Profit Rs 500" in green or "Loss Rs 500" in red.
Widget profitText(BuildContext context, double v, {TextStyle? style}) {
  final good = v >= 0;
  final color = good ? profitColor(context) : lossColor(context);
  final label = good ? 'Profit ${rs(v)}' : 'Loss ${rs(-v)}';
  return Text(label,
      style: (style ?? const TextStyle(fontWeight: FontWeight.w700))
          .copyWith(color: color));
}

// ---------------------------------------------------------------- hero

/// The big purple card at the top of each tab.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.chips = const <Widget>[],
    this.trailing,
  });

  final String label;
  final String value;
  final String? caption;
  final List<Widget> chips;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.purpleLight, AppColors.purpleDark],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.purple.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ],
      ),
    );
  }
}

/// Small translucent box inside a HeroCard.
class HeroChip extends StatelessWidget {
  const HeroChip({super.key, required this.label, required this.value, this.dot});

  final String label;
  final String value;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ]),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Small rounded label, e.g. stock count or "Overdue".
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

// ------------------------------------------------------------ KPI tile

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
    final tint = color ?? scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65)),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800, color: color)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------- category avatar

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.category,
    this.subcategory = '',
    this.size = 46,
  });

  final String category;
  final String subcategory;
  final double size;

  static const List<Color> _palette = [
    AppColors.purple,
    AppColors.coral,
    AppColors.green,
    AppColors.amber,
    Color(0xFF3B82F6),
    Color(0xFFD946A8),
  ];

  IconData get _icon {
    if (category == catLaptop) return Icons.laptop_mac;
    if (category == catComputer) {
      switch (subcategory) {
        case 'All-in-One':
          return Icons.desktop_mac_outlined;
        case 'Mini PC':
          return Icons.developer_board;
        case 'Server':
          return Icons.dns_outlined;
        case 'Gaming PC':
          return Icons.sports_esports_outlined;
        default:
          return Icons.computer;
      }
    }
    switch (subcategory) {
      case 'Keyboard':
        return Icons.keyboard_outlined;
      case 'Mouse':
        return Icons.mouse_outlined;
      case 'Charger':
        return Icons.power_outlined;
      case 'Headphones':
        return Icons.headphones_outlined;
      case 'Bag':
        return Icons.work_outline;
      case 'Battery':
        return Icons.battery_charging_full;
      case 'RAM / SSD':
        return Icons.memory;
      case 'LCD':
      case 'LED':
        return Icons.tv_outlined;
      case 'Graphic card':
        return Icons.videogame_asset_outlined;
      case 'Processor':
        return Icons.developer_board;
      case 'Motherboard':
        return Icons.dashboard_outlined;
      case 'Power supply':
        return Icons.electrical_services;
      case 'Casing':
        return Icons.desktop_windows_outlined;
      case 'Cooler / Fan':
        return Icons.air;
      case 'HDD':
        return Icons.storage_outlined;
      case 'Printer':
        return Icons.print_outlined;
      case 'Webcam':
        return Icons.videocam_outlined;
      case 'Speaker':
        return Icons.speaker_outlined;
      case 'UPS':
        return Icons.battery_charging_full;
      case 'Router / Network':
        return Icons.router_outlined;
      case 'Cable / Adapter':
        return Icons.cable;
      default:
        return Icons.devices_other_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = category == catLaptop ? 'Laptop' : '$category$subcategory';
    final index = key.isEmpty ? 0 : key.codeUnits.fold<int>(0, (a, b) => a + b);
    var color = _palette[index % _palette.length];
    if (category == catLaptop) color = AppColors.purple;
    if (category == catComputer) color = const Color(0xFF3B82F6);
    if (_isDark(context)) {
      color = Color.lerp(color, Colors.white, 0.25) ?? color;
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(_icon, color: color, size: size * 0.5),
    );
  }
}

// --------------------------------------------------------------- charts

class DonutPart {
  const DonutPart(this.value, this.color);

  final double value;
  final Color color;
}

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.parts,
    required this.centerTop,
    required this.centerBottom,
    this.size = 150,
  });

  final List<DonutPart> parts;
  final String centerTop;
  final String centerBottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(
              parts,
              scheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(centerTop,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                Text(centerBottom,
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts, this.track);

  final List<DonutPart> parts;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.13;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);

    var total = 0.0;
    for (final p in parts) {
      if (p.value > 0) total += p.value;
    }
    if (total <= 0) return;
    var start = -math.pi / 2;
    final gap = parts.where((p) => p.value > 0).length > 1 ? 0.05 : 0.0;
    for (final p in parts) {
      if (p.value <= 0) continue;
      final sweep = p.value / total * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = p.color;
      canvas.drawArc(rect, start + gap / 2, math.max(0.001, sweep - gap), false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.parts != parts || old.track != track;
}

class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 160,
  });

  final List<double> values;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var maxValue = 0.0;
    for (final v in values) {
      if (v > maxValue) maxValue = v;
    }
    final area = height - 30;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Builder(builder: (ctx) {
                      var h = maxValue <= 0 ? 4.0 : area * values[i] / maxValue;
                      if (h < 4) h = 4;
                      final last = i == values.length - 1;
                      return Container(
                        height: h,
                        decoration: BoxDecoration(
                          color: last
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Text(
                      i < labels.length ? labels[i] : '',
                      style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurface.withValues(alpha: 0.6)),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------ data + picker

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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
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
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final p = list[i];
                      return ListTile(
                        leading: CategoryAvatar(
                            category: p.category,
                            subcategory: p.subcategory,
                            size: 42),
                        title: Text(p.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          p.typeLabel,
                          if (p.brandModel.isNotEmpty) p.brandModel,
                          if (showCost) 'Cost ${rs(p.lastCost)}',
                        ].join('  ·  ')),
                        trailing: Pill(
                          '${p.stock} in stock',
                          color: p.stock <= 0
                              ? lossColor(context)
                              : profitColor(context),
                        ),
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
