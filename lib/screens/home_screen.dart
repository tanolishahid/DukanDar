import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../perms.dart';
import '../services/files.dart';
import '../services/session.dart';
import '../services/sync.dart';
import '../ui.dart';
import 'credit_tab.dart';
import 'dashboard_tab.dart';
import 'inventory_tab.dart';
import 'sales_tab.dart';
import 'staff_screen.dart';

class _TabDef {
  _TabDef(this.label, this.icon, this.page);

  final String label;
  final IconData icon;
  final Widget page;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  List<_TabDef> _tabs(SessionState s) => [
        _TabDef('Inventory', Icons.inventory_2_outlined, const InventoryTab()),
        if (s.can(Perm.sell))
          _TabDef('Sales', Icons.point_of_sale, const SalesTab()),
        if (s.can(Perm.credit))
          _TabDef('Credit', Icons.account_balance_wallet_outlined,
              const CreditTab()),
        if (s.can(Perm.dashboard))
          _TabDef('Dashboard', Icons.bar_chart, const DashboardTab()),
      ];

  Future<void> _backup() async {
    try {
      final path = await FileOut.backupNow();
      if (mounted) toast(context, 'Backup saved: $path');
    } catch (e) {
      if (mounted) toast(context, 'Backup failed: $e');
    }
  }

  void _showShopInfo(SessionState s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.shopName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signed in as: ${s.displayName} (${s.role})'),
            if (!s.isLocalMode) ...[
              const SizedBox(height: 8),
              SelectableText('Shop code for staff login: ${s.shopCode}'),
              if (s.activeUntil.isNotEmpty) Text('Active until: ${s.activeUntil}'),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                  'Local-only mode: data stays on this device. Add your Supabase '
                  'details in lib/config.dart to turn on cloud sync, backup and staff logins.'),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final sync = context.watch<SyncService>();
    final tabs = _tabs(session);
    if (_index >= tabs.length) _index = 0;
    final wide = MediaQuery.of(context).size.width >= 800;

    final syncIcon = !sync.enabled
        ? const Tooltip(
            message: 'Local only (cloud sync off)',
            child: Icon(Icons.cloud_off_outlined))
        : sync.syncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(sync.offline
                ? Icons.cloud_off
                : (sync.pending > 0
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_done_outlined));

    final syncLabel = !sync.enabled
        ? 'Local only'
        : sync.syncing
            ? 'Syncing...'
            : sync.offline
                ? 'Offline - ${sync.pending} waiting'
                : sync.lastError != null
                    ? 'Sync problem'
                    : sync.pending > 0
                        ? '${sync.pending} waiting'
                        : 'Synced';

    final appBar = AppBar(
      title: Text(session.shopName.isEmpty ? AppConfig.appName : session.shopName),
      actions: [
        InkWell(
          onTap: sync.enabled ? () => sync.syncNow() : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              syncIcon,
              if (wide) ...[const SizedBox(width: 6), Text(syncLabel)],
            ]),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'staff':
                Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const StaffScreen()));
                break;
              case 'backup':
                await _backup();
                break;
              case 'info':
                _showShopInfo(session);
                break;
              case 'sync':
                sync.syncNow();
                break;
              case 'signout':
                final unsynced = sync.pending;
                final ok = await confirmDialog(
                    context,
                    'Sign out?',
                    unsynced > 0 && sync.enabled
                        ? '$unsynced changes have not reached the cloud yet. '
                            'Connect to the internet and sync before signing out, '
                            'or they will upload next time you sign in. Sign out now?'
                        : 'Do you want to sign out?');
                if (ok) await session.signOut();
                break;
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(value: 'info', child: Text('Shop info')),
            if (session.isOwner && !session.isLocalMode)
              const PopupMenuItem(value: 'staff', child: Text('Staff')),
            if (session.isOwner)
              const PopupMenuItem(value: 'backup', child: Text('Backup now')),
            if (sync.enabled)
              const PopupMenuItem(value: 'sync', child: Text('Sync now')),
            if (!session.isLocalMode)
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
          ],
        ),
      ],
    );

    final body = tabs[_index].page;

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final t in tabs)
                  NavigationRailDestination(
                      icon: Icon(t.icon), label: Text(t.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
