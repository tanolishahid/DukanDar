import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../format.dart';
import '../models.dart';
import '../perms.dart';
import '../responsive.dart';
import '../services/repo.dart';
import '../services/session.dart';
import '../services/slip.dart';
import '../theme.dart';
import '../ui.dart';

// ------------------------------------------------------------------ line dialog

class _LineData {
  _LineData(this.qty, this.price, this.cost, this.name);
  final int qty;
  final double price;
  final double cost;
  final String name;
}

/// Asks for quantity and price of one bill line (a stock item or a
/// repair / service).
class _LineDialog extends StatefulWidget {
  const _LineDialog({
    required this.title,
    required this.isService,
    this.maxQty,
    this.qty = 1,
    this.price,
    this.cost,
    this.name = '',
  });

  final String title;
  final bool isService;
  final int? maxQty;
  final int qty;
  final double? price;
  final double? cost;
  final String name;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _price;
  late final TextEditingController _cost;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _qty = TextEditingController(text: '${widget.qty}');
    _price = TextEditingController(
        text: widget.price == null ? '' : _plain(widget.price!));
    _cost = TextEditingController(
        text: (widget.cost == null || widget.cost == 0) ? '' : _plain(widget.cost!));
  }

  String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _ok() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      _LineData(
        widget.isService ? 1 : int.parse(_qty.text.trim()),
        parseNum(_price.text) ?? 0,
        parseNum(_cost.text) ?? 0,
        _name.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showCost = context.read<SessionState>().can(Perm.viewCost);
    return AlertDialog(
      title: Text(widget.title),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isService) ...[
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'What was done',
                    helperText: 'Example: Laptop screen repair',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Write a short description'
                      : null,
                ),
                const SizedBox(height: 12),
              ] else ...[
                TextFormField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    helperText: widget.maxQty == null
                        ? null
                        : '${widget.maxQty} available',
                  ),
                  validator: (v) {
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n < 1) return 'At least 1';
                    if (widget.maxQty != null && n > widget.maxQty!) {
                      return 'Only ${widget.maxQty} left';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _price,
                autofocus: !widget.isService,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.isService
                      ? 'Charge for the customer'
                      : 'Selling price (each)',
                  prefixText: 'Rs ',
                ),
                validator: (v) {
                  final n = parseNum(v ?? '');
                  return (n == null || n < 0) ? 'Enter the price' : null;
                },
              ),
              if (widget.isService && showCost) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'What it cost you (optional)',
                    helperText: 'Parts, labour... not shown on the slip',
                    prefixText: 'Rs ',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _ok, child: const Text('Add')),
      ],
    );
  }
}

// ------------------------------------------------------------------ new bill

class NewBillScreen extends StatefulWidget {
  const NewBillScreen({super.key});

  @override
  State<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends State<NewBillScreen> {
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _discount = TextEditingController();
  final _received = TextEditingController();

  final List<BillLineInput> _lines = [];
  final Map<String, ProductStock> _stock = {};
  bool _payPart = false;
  DateTime _expected = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _note.dispose();
    _discount.dispose();
    _received.dispose();
    super.dispose();
  }

  double get _subtotal => _lines.fold<double>(0.0, (a, l) => a + l.qty * l.price);
  double get _discountValue => parseNum(_discount.text) ?? 0;
  double get _total => _subtotal - _discountValue;

  int _inCart(String productId, {BillLineInput? except}) {
    var n = 0;
    for (final l in _lines) {
      if (l.productId == productId && !identical(l, except)) n += l.qty;
    }
    return n;
  }

  Future<void> _addProduct() async {
    final p = await pickProduct(context);
    if (p == null || !mounted) return;
    final available = p.stock - _inCart(p.id);
    if (available <= 0) {
      toast(context, 'All of this item is already on the bill.');
      return;
    }
    final data = await showDialog<_LineData>(
      context: context,
      builder: (_) => _LineDialog(
          title: p.name, isService: false, maxQty: available),
    );
    if (data == null) return;
    setState(() {
      _stock[p.id] = p;
      _lines.add(BillLineInput(
          productId: p.id, name: p.name, qty: data.qty, price: data.price));
    });
  }

  Future<void> _addService() async {
    final data = await showDialog<_LineData>(
      context: context,
      builder: (_) => const _LineDialog(
          title: 'Repair / service', isService: true),
    );
    if (data == null) return;
    setState(() => _lines.add(BillLineInput(
        name: data.name, qty: 1, price: data.price, extraCost: data.cost)));
  }

  Future<void> _edit(BillLineInput l) async {
    int? max;
    if (!l.isService) {
      final p = _stock[l.productId];
      if (p != null) max = p.stock - _inCart(l.productId, except: l);
    }
    final data = await showDialog<_LineData>(
      context: context,
      builder: (_) => _LineDialog(
        title: l.isService ? 'Repair / service' : l.name,
        isService: l.isService,
        maxQty: max,
        qty: l.qty,
        price: l.price,
        cost: l.extraCost,
        name: l.name,
      ),
    );
    if (data == null) return;
    setState(() {
      l.qty = data.qty;
      l.price = data.price;
      if (l.isService) l.extraCost = data.cost;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _expected,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => _expected = d);
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      toast(context, 'Add at least one item or repair first.');
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<Repo>();
    final err = await repo.addBill(
      customer: _customer.text,
      phone: _phone.text,
      note: _note.text,
      lines: _lines,
      discount: _discountValue,
      paidNow: _payPart ? (parseNum(_received.text) ?? 0) : null,
      expectedDate: _payPart ? isoDay(_expected) : '',
    );
    if (!mounted) return;
    if (err != null) {
      setState(() => _saving = false);
      toast(context, err);
      return;
    }
    final bill = await repo.billById(repo.lastBillId);
    if (!mounted) return;
    if (bill == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
          builder: (_) => BillDetailScreen(bill: bill, justSaved: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _total;
    final received = parseNum(_received.text) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('New bill')),
      body: ListView(
        padding: Responsive.pad(context, Responsive.formWidth(context),
            const EdgeInsets.fromLTRB(16, 8, 16, 32)),
        children: [
          TextField(
            controller: _customer,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Customer name',
                helperText: 'Needed only if the customer will pay later'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration:
                const InputDecoration(labelText: 'Customer phone (optional)'),
          ),
          const SectionTitle('Items on this bill'),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Add what the customer is buying: stock items, a repair, or both.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
              ),
            ),
          for (final l in _lines)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () => _edit(l),
                leading: Icon(l.isService
                    ? Icons.build_outlined
                    : Icons.inventory_2_outlined),
                title: Text(l.name),
                subtitle: Text(l.isService
                    ? 'Repair / service'
                    : '${l.qty} × ${rs(l.price)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(rs(l.qty * l.price),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _lines.remove(l)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.tonalIcon(
              onPressed: _addProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add item from stock'),
            ),
            FilledButton.tonalIcon(
              onPressed: _addService,
              icon: const Icon(Icons.build_outlined),
              label: const Text('Add repair / service'),
            ),
          ]),
          const SectionTitle('Discount and payment'),
          TextField(
            controller: _discount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Discount on the whole bill (optional)',
                prefixText: 'Rs '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row('Subtotal', rs(_subtotal)),
                  if (_discountValue > 0)
                    _row('Discount', '- ${rs(_discountValue)}'),
                  const Divider(),
                  _row('TOTAL', rs(total < 0 ? 0 : total), big: true),
                  if (_payPart && total > 0) ...[
                    _row('Received now', rs(received)),
                    _row('Balance (credit)',
                        rs((total - received) < 0 ? 0 : total - received)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ChoiceTiles<bool>(
            selected: _payPart,
            options: const [
              ChoiceOption(false, 'Paid in full', Icons.check_circle_outline),
              ChoiceOption(true, 'Part / pay later', Icons.schedule),
            ],
            onChanged: (v) => setState(() => _payPart = v),
          ),
          if (_payPart) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _received,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Received now (0 if nothing)', prefixText: 'Rs '),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Customer will pay the rest by'),
                subtitle: Text(fmtDate(_expected)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
                labelText: 'Note on the slip (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: Text(_saving ? 'Saving...' : 'Save bill'),
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: big ? 18 : 14,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w500)),
            Text(v,
                style: TextStyle(
                    fontSize: big ? 20 : 14,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
}

// --------------------------------------------------------------- bill detail

class BillDetailScreen extends StatefulWidget {
  const BillDetailScreen({super.key, required this.bill, this.justSaved = false});

  final BillRow bill;
  final bool justSaved;

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  SlipPaper _paper = SlipPaper.roll80;

  @override
  void initState() {
    super.initState();
    SlipSettings.load().then((p) {
      if (mounted) setState(() => _paper = p);
    });
    if (widget.justSaved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) toast(context, 'Bill saved.');
      });
    }
  }

  Future<void> _print(BillRow bill, {required bool share}) async {
    final s = context.read<SessionState>();
    try {
      if (share) {
        await Slip.share(bill,
            shopName: s.shopName,
            shopPhone: s.shopPhone,
            shopAddress: s.shopAddress,
            paper: _paper);
      } else {
        await Slip.print(bill,
            shopName: s.shopName,
            shopPhone: s.shopPhone,
            shopAddress: s.shopAddress,
            paper: _paper);
      }
    } catch (e) {
      if (mounted) toast(context, 'Could not prepare the slip: $e');
    }
  }

  Future<void> _addPayment(BillRow bill) async {
    final c = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Customer payment'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Amount received',
              helperText: 'Balance: ${rs(bill.balance)}',
              prefixText: 'Rs '),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseNum(c.text)),
              child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (amount == null || !mounted) return;
    final err = await context.read<Repo>().addPayment(bill.creditId, amount);
    if (!mounted) return;
    toast(context, err ?? 'Payment saved.');
  }

  Future<void> _delete(BillRow bill) async {
    final ok = await confirmDialog(context, 'Delete this bill?',
        'Stock will be returned to your inventory and any credit entry for this bill is removed.');
    if (!ok || !mounted) return;
    final err = await context.read<Repo>().deleteBill(bill);
    if (!mounted) return;
    if (err != null) {
      toast(context, err);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final showCost = session.can(Perm.viewCost);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.bill.billNo.isEmpty
              ? 'Sale'
              : 'Bill ${widget.bill.billNo}')),
      body: RepoFuture<BillRow?>(
        load: (repo) =>
            repo.billById(widget.bill.id, near: widget.bill.billedAt),
        builder: (ctx, found) {
          final bill = found;
          if (bill == null) {
            return const Center(child: Text('This bill was deleted.'));
          }
          return ListView(
            padding: Responsive.pad(context, Responsive.formWidth(context),
                const EdgeInsets.fromLTRB(16, 8, 16, 32)),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtDateTime(bill.billedAt),
                          style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.65))),
                      if (bill.customer.isNotEmpty)
                        Text(
                            bill.phone.isEmpty
                                ? bill.customer
                                : '${bill.customer}  ·  ${bill.phone}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      const Divider(height: 24),
                      for (final l in bill.lines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        l.productName.isEmpty
                                            ? 'Item'
                                            : l.productName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                      [
                                        if (l.brandModel.isNotEmpty) l.brandModel,
                                        '${l.qty} × ${rs(l.shownPrice)}',
                                        if (showCost && l.extraCost > 0)
                                          'cost ${rs(l.extraCost)}',
                                      ].join('  ·  '),
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.65)),
                                    ),
                                  ],
                                ),
                              ),
                              Text(rs(l.shownTotal),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      const Divider(height: 20),
                      if (bill.discount > 0.004) ...[
                        _kv('Subtotal', rs(bill.subtotal)),
                        _kv('Discount', '- ${rs(bill.discount)}'),
                      ],
                      _kv('Total', rs(bill.total), big: true),
                      _kv('Paid', rs(bill.paid)),
                      if (bill.hasBalance)
                        _kv('Balance due', rs(bill.balance), big: true),
                      if (showCost) ...[
                        const SizedBox(height: 8),
                        profitText(context, bill.profit),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SlipPaper>(
                value: _paper,
                decoration: const InputDecoration(labelText: 'Slip paper'),
                items: [
                  for (final p in SlipPaper.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _paper = v);
                  SlipSettings.save(v);
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _print(bill, share: false),
                icon: const Icon(Icons.print),
                label: const Text('Print slip'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _print(bill, share: true),
                icon: const Icon(Icons.share),
                label: const Text('Share as PDF (WhatsApp, email...)'),
              ),
              if (bill.hasBalance && bill.creditId.isNotEmpty &&
                  session.can(Perm.credit)) ...[
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () => _addPayment(bill),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Add customer payment'),
                ),
              ],
              if (session.can(Perm.edit)) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _delete(bill),
                  icon: Icon(Icons.delete_outline, color: lossColor(context)),
                  label: Text('Delete this bill',
                      style: TextStyle(color: lossColor(context))),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: big ? 16 : 14,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w500)),
            Text(v,
                style: TextStyle(
                    fontSize: big ? 17 : 14,
                    fontWeight: big ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
}

// ------------------------------------------------------------ shop details

/// Owner edits the shop name, phone and address printed on slips.
Future<void> showShopDetailsDialog(BuildContext context) async {
  final session = context.read<SessionState>();
  final name = TextEditingController(text: session.shopName);
  final phone = TextEditingController(text: session.shopPhone);
  final address = TextEditingController(text: session.shopAddress);
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Shop details'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('These are printed at the top of every slip.'),
              const SizedBox(height: 12),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Shop name')),
              const SizedBox(height: 12),
              TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 12),
              TextField(
                  controller: address,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address')),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await session.updateShopProfile(
                          name: name.text,
                          phone: phone.text,
                          address: address.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setState(() {
                        busy = false;
                        error = friendlyError(e);
                      });
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  phone.dispose();
  address.dispose();
}
