import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../perms.dart';
import '../services/repo.dart';
import '../services/session.dart';
import '../ui.dart';

enum _Filter { unpaid, today, overdue, paid }

class CreditTab extends StatefulWidget {
  const CreditTab({super.key});

  @override
  State<CreditTab> createState() => _CreditTabState();
}

class _CreditTabState extends State<CreditTab> {
  _Filter _filter = _Filter.unpaid;

  static String _label(_Filter f) {
    switch (f) {
      case _Filter.unpaid:
        return 'Unpaid';
      case _Filter.today:
        return 'Due today';
      case _Filter.overdue:
        return 'Overdue';
      case _Filter.paid:
        return 'Paid';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const NewCreditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New credit'),
      ),
      body: RepoFuture<List<CreditRow>>(
        load: (repo) => repo.credits(),
        builder: (ctx, all) {
          var pending = 0.0;
          var dueToday = 0, overdue = 0;
          for (final c in all) {
            if (c.isSettled) continue;
            pending += c.balance;
            if (c.isDueToday) dueToday++;
            if (c.isOverdue) overdue++;
          }
          final list = all.where((c) {
            switch (_filter) {
              case _Filter.unpaid:
                return !c.isSettled;
              case _Filter.today:
                return c.isDueToday;
              case _Filter.overdue:
                return c.isOverdue;
              case _Filter.paid:
                return c.isSettled;
            }
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                        child: KpiTile(
                            label: 'Customers owe you',
                            value: rs(pending),
                            icon: Icons.account_balance_wallet_outlined)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: KpiTile(
                            label: 'Due today',
                            value: '$dueToday',
                            color: dueToday > 0 ? Colors.orange.shade800 : null,
                            icon: Icons.notifications_active_outlined)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: KpiTile(
                            label: 'Overdue',
                            value: '$overdue',
                            color: overdue > 0 ? lossColor(context) : null,
                            icon: Icons.warning_amber_outlined)),
                  ],
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_label(f)),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? const Center(child: Text('Nothing here.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 90, top: 8),
                        itemCount: list.length,
                        itemBuilder: (ctx, i) => _CreditCard(credit: list[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({required this.credit});

  final CreditRow credit;

  @override
  Widget build(BuildContext context) {
    final c = credit;
    Color? chipColor;
    String chipText;
    if (c.isSettled) {
      chipText = 'Paid';
      chipColor = Colors.green.shade700;
    } else if (c.isOverdue) {
      chipText = 'Overdue · ${c.expectedDate}';
      chipColor = Colors.red.shade700;
    } else if (c.isDueToday) {
      chipText = 'Due today';
      chipColor = Colors.orange.shade800;
    } else {
      chipText = 'Due ${c.expectedDate}';
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => CreditDetailScreen(creditId: c.id)),
        ),
        title: Text(c.customerName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          c.productName,
          if (c.phone.isNotEmpty) c.phone,
          chipText,
        ].join('  ·  '),
            style: TextStyle(color: chipColor)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(rs(c.balance),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text('of ${rs(c.totalDue)}',
                style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ new credit

class NewCreditScreen extends StatefulWidget {
  const NewCreditScreen({super.key});

  @override
  State<NewCreditScreen> createState() => _NewCreditScreenState();
}

class _NewCreditScreenState extends State<NewCreditScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _total = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _extra = TextEditingController();
  final _note = TextEditingController();

  ProductStock? _product;
  DateTime _expected = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _qty.dispose();
    _total.dispose();
    _paid.dispose();
    _extra.dispose();
    _note.dispose();
    super.dispose();
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
    if (_product == null) {
      toast(context, 'Choose the product first.');
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final err = await context.read<Repo>().addCredit(
          customerName: _name.text,
          phone: _phone.text,
          productId: _product!.id,
          productName: _product!.name,
          qty: int.parse(_qty.text.trim()),
          totalDue: parseNum(_total.text) ?? 0,
          extraCost: parseNum(_extra.text) ?? 0,
          paidNow: parseNum(_paid.text) ?? 0,
          expectedDate: isoDay(_expected),
          note: _note.text,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      toast(context, err);
    } else {
      toast(context, 'Credit entry saved.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Scaffold(
      appBar: AppBar(title: const Text('New credit (pay later)')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Customer name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter the name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.search),
                title: Text(p == null ? 'Choose product from inventory' : p.name),
                subtitle: p == null
                    ? null
                    : Text('${p.typeLabel}  ·  ${p.stock} in stock'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await pickProduct(context);
                  if (picked != null) setState(() => _product = picked);
                },
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
                    controller: _total,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Total amount due', prefixText: 'Rs '),
                    validator: (v) {
                      final n = parseNum(v ?? '');
                      return (n == null || n <= 0) ? 'Enter the total' : null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _paid,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Paid now',
                helperText: 'Enter 0 if the customer paid nothing yet',
                prefixText: 'Rs ',
              ),
              validator: (v) {
                final n = parseNum(v ?? '');
                final total = parseNum(_total.text) ?? 0;
                if (n == null || n < 0) return 'Enter 0 or an amount';
                if (n > total) return 'More than the total';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _extra,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Extra costs (optional)',
                helperText: 'Delivery, repair...',
                prefixText: 'Rs ',
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Customer will pay on'),
              subtitle: Text(fmtDate(_expected)),
              trailing: TextButton(onPressed: _pickDate, child: const Text('Change')),
            ),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 8),
            const Text('The date given is saved automatically. You get a '
                'reminder on the payment date.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: Text(_saving ? 'Saving...' : 'Save credit entry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- credit detail

class CreditDetailScreen extends StatelessWidget {
  const CreditDetailScreen({super.key, required this.creditId});

  final String creditId;

  Future<void> _addPayment(BuildContext context, CreditRow c) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payment from ${c.customerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Balance: ${rs(c.balance)}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Amount received', prefixText: 'Rs '),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.balance),
              child: const Text('Full balance')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseNum(controller.text)),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (amount == null) return;
    if (!context.mounted) return;
    final err = await context.read<Repo>().addPayment(c.id, amount);
    if (!context.mounted) return;
    toast(context, err ?? 'Payment saved.');
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return RepoFuture<(CreditRow?, List<PaymentRow>)>(
      load: (repo) async {
        final all = await repo.credits();
        final match = all.where((c) => c.id == creditId);
        if (match.isEmpty) return (null, <PaymentRow>[]);
        return (match.first, await repo.paymentsOf(creditId));
      },
      builder: (ctx, data) {
        final c = data.$1;
        final pays = data.$2;
        if (c == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This entry was deleted.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(c.customerName),
            actions: [
              if (session.can(Perm.edit))
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirmDialog(
                        context,
                        'Delete this credit entry?',
                        'Its payments will be removed and the stock goes back to your inventory.');
                    if (!ok) return;
                    await context.read<Repo>().deleteCredit(c.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
          floatingActionButton: c.isSettled
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _addPayment(context, c),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Add payment'),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              if (c.phone.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_outlined),
                  title: SelectableText(c.phone),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shopping_bag_outlined),
                title: Text('${c.qty} × ${c.productName}'),
                subtitle: Text('Given on ${fmtDate(c.takenAt)}'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text('Expected payment: ${c.expectedDate}'),
              ),
              if (c.note.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notes),
                  title: Text(c.note),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: KpiTile(label: 'Total', value: rs(c.totalDue))),
                const SizedBox(width: 8),
                Expanded(
                    child: KpiTile(
                        label: 'Paid',
                        value: rs(c.paid),
                        color: profitColor(context))),
                const SizedBox(width: 8),
                Expanded(
                    child: KpiTile(
                        label: 'Balance',
                        value: rs(c.balance < 0 ? 0 : c.balance),
                        color: c.isSettled ? null : lossColor(context))),
              ]),
              const SizedBox(height: 20),
              Text('Payments', style: Theme.of(context).textTheme.titleMedium),
              if (pays.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No payments yet.'),
                ),
              for (final p in pays)
                Card(
                  child: ListTile(
                    title: Text(rs(p.amount)),
                    subtitle: Text(fmtDateTime(p.paidAt)),
                    trailing: session.can(Perm.edit)
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final ok = await confirmDialog(context,
                                  'Delete this payment?', 'The balance will go back up.');
                              if (ok && context.mounted) {
                                await context.read<Repo>().deletePayment(p.id);
                              }
                            },
                          )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
