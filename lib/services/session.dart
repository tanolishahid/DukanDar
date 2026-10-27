import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../db/app_db.dart';
import '../perms.dart';

class StaffMember {
  StaffMember({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.perms,
    required this.active,
  });

  final String userId;
  final String username;
  final String displayName;
  final List<String> perms;
  final bool active;
}

/// Who is signed in, which shop they belong to and what they may do.
/// The details are kept on the device, so the app still opens with no internet.
class SessionState extends ChangeNotifier {
  SessionState(this._prefs);

  final SharedPreferences _prefs;

  bool loggedIn = false;
  String role = 'owner';
  String shopId = 'local';
  String shopName = 'My Shop';
  String shopCode = '';
  String userId = 'local';
  String displayName = 'Owner';
  Set<String> perms = <String>{};
  String activeUntil = '';
  bool memberActive = true;

  bool get isOwner => role == 'owner';
  bool get isLocalMode => !AppConfig.isConfigured;
  bool can(String p) => isOwner || perms.contains(p);

  /// True when the developer has switched this shop off (unpaid) or the
  /// owner has switched this staff member off.
  bool get blocked {
    if (!AppConfig.isConfigured || !loggedIn) return false;
    if (!memberActive) return true;
    if (activeUntil.isNotEmpty) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (today.compareTo(activeUntil) > 0) return true;
    }
    return false;
  }

  String get blockedReason {
    if (!memberActive) {
      return 'Your access has been switched off by the shop owner.';
    }
    return 'This shop\'s subscription ended on $activeUntil. '
        'Please contact the app provider to renew.';
  }

  SupabaseClient get _client => Supabase.instance.client;

  // ------------------------------------------------------------- start up

  Future<void> load() async {
    if (!AppConfig.isConfigured) {
      loggedIn = true;
      role = 'owner';
      shopId = 'local';
      shopName = _prefs.getString('local_shop_name') ?? 'My Shop';
      displayName = 'Owner';
      userId = 'local';
      notifyListeners();
      return;
    }
    final raw = _prefs.getString('session');
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _apply(m);
      // The sign-in token is stored by the Supabase library itself.
      loggedIn = _client.auth.currentSession != null;
    } catch (_) {
      loggedIn = false;
    }
    notifyListeners();
    if (loggedIn) {
      refreshMembership();
    }
  }

  void _apply(Map<String, dynamic> m) {
    role = (m['role'] ?? 'owner') as String;
    shopId = (m['shopId'] ?? '') as String;
    shopName = (m['shopName'] ?? '') as String;
    shopCode = (m['shopCode'] ?? '') as String;
    userId = (m['userId'] ?? '') as String;
    displayName = (m['displayName'] ?? '') as String;
    perms = ((m['perms'] ?? <dynamic>[]) as List<dynamic>)
        .map((e) => e.toString())
        .toSet();
    activeUntil = (m['activeUntil'] ?? '') as String;
    memberActive = (m['active'] ?? true) as bool;
  }

  Future<void> _save() async {
    await _prefs.setString(
      'session',
      jsonEncode({
        'role': role,
        'shopId': shopId,
        'shopName': shopName,
        'shopCode': shopCode,
        'userId': userId,
        'displayName': displayName,
        'perms': perms.toList(),
        'activeUntil': activeUntil,
        'active': memberActive,
      }),
    );
  }

  Future<void> setLocalShopName(String name) async {
    shopName = name;
    await _prefs.setString('local_shop_name', name);
    notifyListeners();
  }

  // -------------------------------------------------------------- sign in

  /// A new shop owner creates an account and their shop.
  Future<void> registerOwner({
    required String email,
    required String password,
    required String shopName,
    required String ownerName,
  }) async {
    final res = await _client.auth.signUp(email: email, password: password);
    if (res.session == null) {
      throw 'Sign-up needs email confirmation. In Supabase turn OFF '
          '"Confirm email" (Authentication > Providers > Email).';
    }
    await _client.rpc('create_shop', params: {
      'p_shop_name': shopName,
      'p_display_name': ownerName,
    });
    await _loadMembership();
  }

  Future<void> signInOwner(String email, String password) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    await _loadMembership();
  }

  String staffEmail(String shopCode, String username) =>
      '${_clean(username)}.${_clean(shopCode)}@${AppConfig.staffEmailDomain}';

  String _clean(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> signInStaff(
      String shopCode, String username, String password) async {
    await _client.auth.signInWithPassword(
      email: staffEmail(shopCode, username),
      password: password,
    );
    await _loadMembership();
    // Remember the shop on this phone so staff only type username + password next time.
    await _prefs.setString('saved_shop_code', shopCode.trim().toUpperCase());
    await _prefs.setString('saved_username', username.trim());
  }

  String? get savedShopCode => _prefs.getString('saved_shop_code');
  String? get savedUsername => _prefs.getString('saved_username');

  Future<void> forgetSavedShop() async {
    await _prefs.remove('saved_shop_code');
    await _prefs.remove('saved_username');
  }

  Future<void> _loadMembership() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw 'Sign-in failed.';
    final m = await _client
        .from('shop_members')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    if (m == null) {
      await _client.auth.signOut();
      throw 'No shop is linked to this account.';
    }
    final shop = await _client
        .from('shops')
        .select()
        .eq('id', m['shop_id'] as String)
        .maybeSingle();
    if (shop == null) {
      await _client.auth.signOut();
      throw 'Shop not found.';
    }
    if (m['active'] == false) {
      await _client.auth.signOut();
      throw 'Your access has been switched off by the shop owner.';
    }

    final newShopId = m['shop_id'] as String;
    // A different shop on the same device: remove the old shop's local data.
    final oldShop = _prefs.getString('db_shop_id');
    if (oldShop != null && oldShop != newShopId) {
      await AppDb.instance.wipe();
      for (final t in AppDb.syncTables) {
        await _prefs.remove('pull_$t');
      }
    }
    await _prefs.setString('db_shop_id', newShopId);

    _apply({
      'role': m['role'],
      'shopId': newShopId,
      'shopName': shop['name'],
      'shopCode': shop['code'],
      'userId': uid,
      'displayName': m['display_name'] ?? '',
      'perms': m['perms'] ?? <dynamic>[],
      'activeUntil': shop['active_until'] ?? '',
      'active': m['active'] ?? true,
    });
    loggedIn = true;
    await _save();
    notifyListeners();
  }

  /// Re-reads permissions and the subscription date when online.
  /// Quietly does nothing when offline.
  Future<void> refreshMembership() async {
    if (!AppConfig.isConfigured || !loggedIn) return;
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      final m = await _client
          .from('shop_members')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (m == null) return;
      final shop = await _client
          .from('shops')
          .select()
          .eq('id', m['shop_id'] as String)
          .maybeSingle();
      if (shop == null) return;
      _apply({
        'role': m['role'],
        'shopId': m['shop_id'],
        'shopName': shop['name'],
        'shopCode': shop['code'],
        'userId': uid,
        'displayName': m['display_name'] ?? '',
        'perms': m['perms'] ?? <dynamic>[],
        'activeUntil': shop['active_until'] ?? '',
        'active': m['active'] ?? true,
      });
      await _save();
      notifyListeners();
    } catch (_) {
      // offline or temporary error: keep what is stored on the device
    }
  }

  Future<void> signOut() async {
    if (AppConfig.isConfigured) {
      try {
        await _client.auth.signOut();
      } catch (_) {}
      await _prefs.remove('session');
    }
    loggedIn = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- staff

  Future<List<StaffMember>> listStaff() async {
    final rows = await _client
        .from('shop_members')
        .select()
        .eq('shop_id', shopId)
        .eq('role', 'staff')
        .order('created_at');
    return rows
        .map((r) => StaffMember(
              userId: r['user_id'] as String,
              username: (r['username'] ?? '') as String,
              displayName: (r['display_name'] ?? '') as String,
              perms: ((r['perms'] ?? <dynamic>[]) as List<dynamic>)
                  .map((e) => e.toString())
                  .toList(),
              active: (r['active'] ?? true) as bool,
            ))
        .toList();
  }

  /// Only the owner can do this. A second, temporary connection is used to
  /// create the staff login so the owner stays signed in.
  Future<void> createStaff({
    required String username,
    required String displayName,
    required String password,
    required List<String> perms,
  }) async {
    if (!isOwner) throw 'Only the owner can add staff.';
    final clean = _clean(username);
    if (clean.isEmpty) throw 'Username can only use letters and numbers.';
    final temp = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    try {
      final res = await temp.auth.signUp(
        email: staffEmail(shopCode, clean),
        password: password,
      );
      final uid = res.user?.id;
      if (uid == null) {
        throw 'Could not create the staff login. Try a different username.';
      }
      await _client.from('shop_members').insert({
        'user_id': uid,
        'shop_id': shopId,
        'role': 'staff',
        'username': clean,
        'display_name': displayName,
        'perms': perms,
        'active': true,
      });
    } finally {
      await temp.dispose();
    }
  }

  Future<void> updateStaff(String staffUserId,
      {List<String>? perms, bool? active}) async {
    final patch = <String, Object?>{};
    if (perms != null) patch['perms'] = perms;
    if (active != null) patch['active'] = active;
    if (patch.isEmpty) return;
    await _client
        .from('shop_members')
        .update(patch)
        .eq('user_id', staffUserId);
  }
}

String friendlyError(Object e) {
  if (e is AuthException) {
    final m = e.message;
    if (m.toLowerCase().contains('invalid login')) {
      return 'Wrong email/username or password.';
    }
    if (m.toLowerCase().contains('already registered')) {
      return 'That username or email is already taken.';
    }
    return m;
  }
  if (e is PostgrestException) return e.message;
  final s = e.toString();
  if (s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup')) {
    return 'No internet connection. Please connect and try again.';
  }
  return s.replaceFirst('Exception: ', '');
}
