import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/files.dart';
import '../services/importer.dart';
import '../services/repo.dart';
import '../ui.dart';

/// Add a whole stock list from an Excel or CSV file in one go.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _fileName;
  ParsedTable? _table;
  Map<String, int> _map = {};
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    setState(() {
      _error = null;
    });
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
      final table = Importer.parse(file.name, bytes);
      setState(() {
        _fileName = file.name;
        _table = table;
        _map = Importer.autoMap(table.headers);
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
          'DukanDar_inventory_template.xlsx', Importer.template());
      if (mounted) toast(context, 'Sample file saved: $path');
    } catch (e) {
      if (mounted) toast(context, 'Could not create the sample file: $e');
    }
  }

  Future<void> _import(ConvertResult converted) async {
    setState(() => _busy = true);
    final result = await context.read<Repo>().importRows(converted.ok);
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
              Text('${result.batches} lines added '
                  '(${result.newProducts} new products).'),
              Text('${result.units} units, worth ${rs(result.value)} at purchase price.'),
              if (result.skipped.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('${result.skipped.length} skipped:',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final s in result.skipped.take(8)) Text('• $s'),
                if (result.skipped.length > 8)
                  Text('...and ${result.skipped.length - 8} more'),
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
    final table = _table;
    final ConvertResult? converted =
        table == null ? null : Importer.convert(table, _map);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Import from file')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.upload_file, color: scheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Already have your stock in a file?',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      'Choose an Excel (.xlsx) or CSV file. DukanDar finds the '
                      'columns by itself, shows you a preview, and adds everything '
                      'to your inventory with the totals worked out.\n\n'
                      'A PDF list? Open it in Excel or Google Sheets, save it as '
                      '.xlsx or .csv, then choose that file.'),
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    FilledButton.icon(
                      onPressed: _pick,
                      icon: const Icon(Icons.folder_open),
                      label: Text(_fileName == null ? 'Choose file' : 'Choose another'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _template,
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
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65))),
            const SizedBox(height: 10),
            for (final field in ImportField.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<int>(
                  value: _map[field] ?? -1,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: ImportField.labels[field]),
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
                  onChanged: (v) => setState(() {
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
                      '${converted.ok.length} products ready  ·  '
                      '${converted.units} units  ·  ${rs(converted.value)}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    if (converted.problems.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            '${converted.problems.length} rows will be skipped',
                            style: TextStyle(color: lossColor(context))),
                      ),
                    const SizedBox(height: 10),
                    for (final r in converted.ok.take(5))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: CategoryAvatar(
                            category: r.category,
                            subcategory: r.subcategory,
                            size: 38),
                        title: Text(r.name),
                        subtitle: Text([
                          r.category == 'Accessory' && r.subcategory.isNotEmpty
                              ? r.subcategory
                              : r.category,
                          if (r.brand.isNotEmpty) r.brand,
                          if (r.model.isNotEmpty) r.model,
                        ].join('  ·  ')),
                        trailing: Text('${r.qty} × ${rs(r.unitCost)}'),
                      ),
                    if (converted.ok.length > 5)
                      Text('...and ${converted.ok.length - 5} more'),
                    if (converted.problems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final p in converted.problems.take(5))
                        Text('• $p',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurface.withValues(alpha: 0.7))),
                      if (converted.problems.length > 5)
                        Text('...and ${converted.problems.length - 5} more'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  (_busy || converted.ok.isEmpty) ? null : () => _import(converted),
              icon: const Icon(Icons.check),
              label: Text(_busy
                  ? 'Importing...'
                  : 'Add ${converted.ok.length} products to inventory'),
            ),
            const SizedBox(height: 8),
            Text(
              'Each line is added as a new purchase dated today. Products that '
              'already exist get more stock instead of a duplicate. Items with a '
              'serial number are added one at a time.',
              style: TextStyle(
                  fontSize: 12.5, color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ],
        ],
      ),
    );
  }
}
