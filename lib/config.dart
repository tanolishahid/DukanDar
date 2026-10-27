/// Fill these two values after creating your Supabase project
/// (Supabase dashboard -> Project Settings -> API).
/// While they are left as YOUR_..., the app runs in "local only" mode:
/// everything works on this device, with no login and no cloud sync.
class AppConfig {
  static const String supabaseUrl = 'https://todivyrzraoohpaehnpe.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRvZGl2eXJ6cmFvb2hwYWVobnBlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMwNjcwNTMsImV4cCI6MjEwODY0MzA1M30.Y4blnrN7890kLILk4SeCd7N9OVGO8KTR3JbX5GWTHnc';

  static const String appName = 'DukanDar';

  /// Staff do not have real emails. Their login is built from
  /// username + shop code on this fake domain.
  static const String staffEmailDomain = 'staff.dukandar.app';

  static bool get isConfigured =>
      !supabaseUrl.startsWith('YOUR_') && !supabaseAnonKey.startsWith('YOUR_');
}
