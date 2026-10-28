import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../responsive.dart';
import '../services/files.dart';
import '../services/importer.dart';
import '../services/past_importer.dart';
import '../services/repo.dart';
import '../ui.dart';

/// Brings years of old sales (from an Excel / CSV file) into the app.
class PastImportScreen extends StatefulWidget {
  const PastImportScreen({super.key});

  @override
  State<PastImportScreen> createState() => _PastImportScreenState();
}

class _PastImportScreenState extends State<PastImportScreen> {
  String? _fileName;
  ParsedTable? _table;
  Map<String, int> _map = {};
  String? _error;
  bool _busy = false;
  double _progress = 0;

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _error = 'Could not read that file. Please try again.');
        return;
      }
      final table = PastImporter.parse(file.name, bytes);
      setState(() {
        _fileName = file.name;
        _table = table;
        _map = PastImporter.autoMap(table.headers);
      });
    } catch (e) {
      setState(() {
        _table = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _template() async {
    try {
      final path = await FileOut.save(
          'DukanDar_past_sales_template.xlsx', PastImporter.template());
      if (mounted) toast(context, 'Sample file saved: $path');
    } catch (e) {
      if (mounted) toast(context, 'Could not create the sample file: $e');
    }
  }

  Future<void> _import(PastConvertResult converted) async {
    final ok = await confirmDialog(
        context,
        'Import ${converted.bills.length} bills?',
        'They will be added to your sales history. Your current stock is not '
            'changed. Importing the same file twice adds the bills twice.');
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    final repo = context.read<Repo>();
    var done = 0;
    final problems = <String>[...converted.problems];
    const chunk = 400;
    for (var i = 0; i < converted.bills.length; i += chunk) {
      final end = (i + chunk < converted.bills.length)
          ? i + chunk
          : converted.bills.length;
      final r = await repo.importPastBills(converted.bills.sublist(i, end));
      done += r.bills;
      problems.addAll(r.problems);
      if (!mounted) return;
      setState(() => _progress = end / converted.bills.length);
      // Let the screen breathe between chunks.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import finished'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$done bills added to your sales history.'),
              if (problems.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('${problems.length} rows were skipped:',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final s in problems.take(8)) Text('• $s'),
                if (problems.length > 8)
                  Text('...and ${problems.length - 8} more'),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final table = _table;
    final PastConvertResult? converted =
        table == null ? null : PastImporter.convert(table, _map);

    return Scaffold(
      appBar: AppBar(title: const Text('Import past sales')),
      body: ListView(
        padding: Responsive.pad(context, Responsive.formWidth(context),
            const EdgeInsets.fromLTRB(16, 8, 16, 32)),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.history, color: scheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Add your old sales',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      'Bring in years of past sales from an Excel (.xlsx) or '
                      'CSV file, so reports and the dashboard show your full '
                      'history.\n\n'
                      '• One row per item sold. Use the same Bill no on every row of one bill.\n'
                      '• Old sales do not change your current stock.\n'
                      '• Put a Cost price if you want profit for past months.\n'
                      '• "Amount received" is for the whole bill. If it is less than the '
                      'total, the rest is added to Credit.\n'
                      '• Very large files: import one year at a time.'),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.folder_open),
                      label: Text(
                          _fileName == null ? 'Choose file' : 'Choose another'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _template,
                      icon: const Icon(Icons.download),
                      label: const Text('Sample file'),
                    ),
                  ]),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                ],
              ),
            ),
          ),
          if (table != null && converted != null) ...[
            const SectionTitle('Check the columns'),
            Text('File: $_fileName  ·  ${table.rows.length} rows',
                style:
                    TextStyle(color: scheme.onSurface.withValues(alpha: 0.65))),
            const SizedBox(height: 10),
            for (final field in PastField.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<int>(
                  value: _map[field] ?? -1,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: PastField.labels[field]),
                  items: [
                    const DropdownMenuItem<int>(
                        value: -1, child: Text('- not in my file -')),
                    for (var i = 0; i < table.headers.length; i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(
                          table.headers[i].isEmpty
                              ? 'Column ${i + 1}'
                              : table.headers[i],
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                            if (v == null || v < 0) {
                              _map.remove(field);
                            } else {
                              _map[field] = v;
                            }
                          }),
                ),
              ),
            const SectionTitle('Preview'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${converted.bills.length} bills  ·  ${converted.lineCount} items',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    if (converted.first != null && converted.last != null)
                      Text(
                          'From ${fmtDate(converted.first!)} to ${fmtDate(converted.last!)}'),
                    Text('Sales worth ${rs(converted.total)}'),
                    if (converted.problems.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('${converted.problems.length} rows will be skipped:',
                          style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w700)),
                      for (final p in converted.problems.take(5)) Text('• $p'),
                      if (converted.problems.length > 5)
                        Text('...and ${converted.problems.length - 5} more'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_busy) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('Importing... ${(_progress * 100).round()}%'),
            ] else
              FilledButton.icon(
                onPressed: (!_map.containsKey(PastField.date) ||
                        !_map.containsKey(PastField.item) ||
                        !_map.containsKey(PastField.price) ||
                        converted.bills.isEmpty)
                    ? null
                    : () => _import(converted),
                icon: const Icon(Icons.check),
                label: Text('Import ${converted.bills.length} bills'),
              ),
          ],
        ],
      ),
    );
  }
}
