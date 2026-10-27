/// Fill these two values after creating your Supabase project
/// (Supabase dashboard -> Project Settings -> API).
/// While they are left as YOUR_..., the app runs in "local only" mode:
/// everything works on this device, with no login and no cloud sync.
class AppConfig {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  static const String appName = 'DukanDar';

  /// Staff do not have real emails. Their login is built from
  /// username + shop code on this fake domain.
  static const String staffEmailDomain = 'staff.dukandar.app';

  static bool get isConfigured =>
      !supabaseUrl.startsWith('YOUR_') && !supabaseAnonKey.startsWith('YOUR_');
}
