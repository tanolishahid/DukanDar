import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../perms.dart';
import '../services/session.dart';
import '../ui.dart';

/// Owner only: add staff and choose what each person may do.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  late Future<List<StaffMember>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<SessionState>().listStaff();
  }

  void _reload() {
    setState(() {
      _future = context.read<SessionState>().listStaff();
    });
  }

  Future<void> _add() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => const _StaffDialog(),
    );
    if (done == true) _reload();
  }

  Future<void> _edit(StaffMember m) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffDialog(member: m),
    );
    if (done == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add staff'),
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SelectableText(
                      'Shop code: ${session.shopCode}\n'
                      'Staff sign in with this shop code, their username and password.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<StaffMember>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Center(
                      child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(friendlyError(snap.error!),
                        textAlign: TextAlign.center),
                  ));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return const Center(
                      child: Text('No staff yet. Tap "Add staff".'));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    final m = list[i];
                    return Card(
                      margin:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        onTap: () => _edit(m),
                        leading: CircleAvatar(
                            child: Text(m.displayName.isEmpty
                                ? '?'
                                : m.displayName[0].toUpperCase())),
                        title: Text(m.displayName),
                        subtitle: Text(
                            '@${m.username}  ·  ${m.active ? 'Active' : 'Switched off'}\n'
                            '${m.perms.map((p) => Perm.labels[p] ?? p).join(', ')}'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.edit_outlined),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffDialog extends StatefulWidget {
  const _StaffDialog({this.member});

  final StaffMember? member;

  @override
  State<_StaffDialog> createState() => _StaffDialogState();
}

class _StaffDialogState extends State<_StaffDialog> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  late Set<String> _perms;
  bool _active = true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.member == null;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    if (m == null) {
      _perms = Perm.defaultStaff.toSet();
    } else {
      _perms = m.perms.toSet();
      _active = m.active;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = context.read<SessionState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isNew) {
        if (_name.text.trim().isEmpty ||
            _username.text.trim().isEmpty ||
            _password.text.length < 6) {
          throw 'Enter a name, a username and a password of at least 6 characters.';
        }
        await session.createStaff(
          username: _username.text,
          displayName: _name.text.trim(),
          password: _password.text,
          perms: _perms.toList(),
        );
      } else {
        await session.updateStaff(widget.member!.userId,
            perms: _perms.toList(), active: _active);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Add staff member' : widget.member!.displayName),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isNew) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(
                      labelText: 'Username', helperText: 'Letters and numbers only'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 12),
              ] else
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Can sign in'),
                  subtitle: const Text('Switch off to remove their access'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              const Text('This person can:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              for (final p in Perm.all)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(Perm.labels[p] ?? p),
                  value: _perms.contains(p),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _perms.add(p);
                    } else {
                      _perms.remove(p);
                    }
                  }),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save')),
      ],
    );
  }
}
