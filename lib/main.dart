import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'db/app_db.dart';
import 'screens/blocked_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/reminders.dart';
import 'services/repo.dart';
import 'services/session.dart';
import 'services/sync.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppDb.instance.open();

  if (AppConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Supabase start-up problem: $e');
    }
  }

  final prefs = await SharedPreferences.getInstance();
  final session = SessionState(prefs);
  await session.load();
  final repo = Repo(session);
  final sync = SyncService(session, repo, prefs);
  final themeState = ThemeState(prefs);

  await Reminders.instance.init();
  sync.start();
  repo.rescheduleReminders();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionState>.value(value: session),
        ChangeNotifierProvider<Repo>.value(value: repo),
        ChangeNotifierProvider<SyncService>.value(value: sync),
        ChangeNotifierProvider<ThemeState>.value(value: themeState),
      ],
      child: const DukanDarApp(),
    ),
  );
}

class DukanDarApp extends StatelessWidget {
  const DukanDarApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeState>();
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeState.mode,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    if (!session.loggedIn) return const LoginScreen();
    if (session.blocked) return const BlockedScreen();
    return const HomeScreen();
  }
}
