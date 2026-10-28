import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../db/app_db.dart';
import 'repo.dart';
import 'session.dart';

/// Copies changes between this device and the cloud (Supabase).
///  - push: everything saved here that is not uploaded yet
///  - pull: everything other devices changed since the last pull
/// Rows are identified by a random id and are never hard-deleted, so two
/// devices working offline can never overwrite each other's sales.
class SyncService extends ChangeNotifier {
  SyncService(this.session, this.repo, this.prefs);

  final SessionState session;
  final Repo repo;
  final SharedPreferences prefs;

  bool syncing = false;
  bool offline = false;
  String? lastError;
  DateTime? lastSync;
  int pending = 0;

  Timer? _timer;
  Timer? _debounce;
  int _cycles = 0;
  bool _wasLoggedIn = false;

  bool get enabled => AppConfig.isConfigured;

  void start() {
    repo.onLocalChange = _scheduleSoon;
    refreshPending();
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => syncNow());
    // Start syncing as soon as someone signs in.
    _wasLoggedIn = session.loggedIn;
    session.addListener(() {
      if (session.loggedIn && !_wasLoggedIn) {
        repo.rescheduleReminders();
        syncNow();
      }
      _wasLoggedIn = session.loggedIn;
    });
    syncNow();
  }

  void _scheduleSoon() {
    refreshPending();
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  Future<void> refreshPending() async {
    pending = await AppDb.instance.pendingCount();
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (!enabled || !session.loggedIn || syncing) return;
    if (session.shopId == 'local' || session.shopId.isEmpty) return;
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;

    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await _push(client).timeout(const Duration(seconds: 60));
      await _pull(client).timeout(const Duration(minutes: 10));
      lastSync = DateTime.now();
      offline = false;
      _cycles++;
      if (_cycles % 5 == 1) {
        await session.refreshMembership();
      }
      repo.refresh();
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('ClientException') ||
          s.contains('Failed host lookup') ||
          s.contains('TimeoutException')) {
        offline = true;
      } else {
        lastError = friendlyError(e);
      }
    }
    syncing = false;
    await refreshPending();
  }

  Future<void> _push(SupabaseClient client) async {
    final db = AppDb.instance.db;
    for (final t in AppDb.syncTables) {
      while (true) {
        final rows = await db.query(t, where: 'synced = 0', limit: 500);
        if (rows.isEmpty) break;
        final payload = rows.map((r) {
          final m = Map<String, Object?>.from(r);
          m.remove('synced');
          return m;
        }).toList();
        await client.from(t).upsert(payload, onConflict: 'id');
        final batch = db.batch();
        for (final r in rows) {
          batch.update(
            t,
            {'synced': 1},
            where: 'id = ? AND updated_at = ?',
            whereArgs: [r['id'], r['updated_at']],
          );
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<void> _pull(SupabaseClient client) async {
    final db = AppDb.instance.db;
    for (final t in AppDb.syncTables) {
      var last = prefs.getString('pull_$t') ?? '1970-01-01T00:00:00.000Z';
      while (true) {
        final filterTs = DateTime.tryParse(last)?.toUtc().toIso8601String() ??
            '1970-01-01T00:00:00.000Z';
        final rows = await client
            .from(t)
            .select()
            .gt('server_ts', filterTs)
            .order('server_ts', ascending: true)
            .limit(1000);
        if (rows.isEmpty) break;

        await db.transaction((txn) async {
          for (final r in rows) {
            final m = Map<String, Object?>.from(r);
            final ts = m.remove('server_ts');
            if (ts != null) last = ts.toString();
            final id = m['id'] as String;
            final existing = await txn.query(t,
                columns: ['updated_at', 'synced'],
                where: 'id = ?',
                whereArgs: [id]);
            if (existing.isNotEmpty) {
              final localNewer = existing.first['synced'] == 0 &&
                  (existing.first['updated_at'] as String)
                          .compareTo((m['updated_at'] ?? '') as String) >
                      0;
              if (localNewer) continue;
            }
            m['synced'] = 1;
            await txn.insert(t, m,
                conflictAlgorithm: ConflictAlgorithm.replace);
          }
        });
        await prefs.setString('pull_$t', last);
        if (rows.length < 1000) break;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
