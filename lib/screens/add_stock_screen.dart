import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/repo.dart';
import '../ui.dart';

/// Add stock: a brand new product, or more units of an existing one.
class AddStockScreen extends StatefulWidget {
  const AddStockScreen({super.key, this.existing});

  final ProductStock? existing;

  @override
  State<AddStockScreen> createState() => _AddStockScreenState();
}

class _AddStockScreenState extends State<AddStockScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _cost = TextEditingController();
  final _serial = TextEditingController();
  final _otherType = TextEditingController();

  String _category = catLaptop;
  String _type = accessoryTypes.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _brand.text = e.brand;
      _model.text = e.model;
      _category = e.category;
      _type = e.subcategory;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _model.dispose();
    _qty.dispose();
    _cost.dispose();
    _serial.dispose();
    _otherType.dispose();
    super.dispose();
  }

  String get _subcategory {
    if (_category != catAccessory) return '';
    if (_type == 'Other') return _otherType.text.trim();
    return _type;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = context.read<Repo>();
    final err = await repo.addPurchase(
      existingProductId: widget.existing?.id,
      name: _name.text,
      category: _category,
      subcategory: _subcategory,
      brand: _brand.text,
      model: _model.text,
      qty: int.parse(_qty.text.trim()),
      unitCost: parseNum(_cost.text) ?? 0,
      serial: _serial.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      toast(context, err);
    } else {
      toast(context, 'Stock added.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(locked ? 'Buy more: ${widget.existing!.name}' : 'Add stock')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              enabled: !locked,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Product name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter the product name' : null,
            ),
            const SizedBox(height: 16),
            IgnorePointer(
              ignoring: locked,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: catLaptop,
                      label: Text('Laptop'),
                      icon: Icon(Icons.laptop)),
                  ButtonSegment(
                      value: catAccessory,
                      label: Text('Accessory'),
                      icon: Icon(Icons.mouse_outlined)),
                ],
                selected: {_category},
                onSelectionChanged: (s) => setState(() => _category = s.first),
              ),
            ),
            if (_category == catAccessory && !locked) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: accessoryTypes.contains(_type) ? _type : 'Other',
                decoration: const InputDecoration(labelText: 'Accessory type'),
                items: [
                  for (final t in accessoryTypes)
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'Other'),
              ),
              if (_type == 'Other') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otherType,
                  decoration: const InputDecoration(labelText: 'Type (e.g. Cooling pad)'),
                ),
              ],
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _brand,
                    enabled: !locked,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Brand (e.g. HP)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _model,
                    enabled: !locked,
                    decoration:
                        const InputDecoration(labelText: 'Model (e.g. ProBook 450)'),
                  ),
                ),
              ],
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
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n < 1) ? 'At least 1' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _cost,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Purchase price (each)', prefixText: 'Rs '),
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
              controller: _serial,
              decoration: const InputDecoration(
                labelText: 'Serial number (optional)',
                helperText: 'Add one item at a time when you enter a serial number',
              ),
            ),
            const SizedBox(height: 8),
            const Text('The purchase date is saved automatically.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save to inventory'),
            ),
          ],
        ),
      ),
    );
  }
}
