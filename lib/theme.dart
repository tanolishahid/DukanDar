import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const Color purple = Color(0xFF5B3FD6);
  static const Color purpleLight = Color(0xFF6D50EA);
  static const Color purpleDark = Color(0xFF3F2AA6);
  static const Color green = Color(0xFF22B07D);
  static const Color coral = Color(0xFFFF6B4A);
  static const Color amber = Color(0xFFE9B949);
}

/// Light / Dark / follow the phone. The choice is remembered.
class ThemeState extends ChangeNotifier {
  ThemeState(this._prefs) {
    final v = _prefs.getString('theme_mode');
    if (v == 'light') {
      mode = ThemeMode.light;
    } else if (v == 'dark') {
      mode = ThemeMode.dark;
    } else {
      mode = ThemeMode.system;
    }
  }

  final SharedPreferences _prefs;
  ThemeMode mode = ThemeMode.system;

  Future<void> setMode(ThemeMode m) async {
    mode = m;
    notifyListeners();
    final text = m == ThemeMode.light
        ? 'light'
        : (m == ThemeMode.dark ? 'dark' : 'system');
    await _prefs.setString('theme_mode', text);
  }
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.purple,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFF9D86FF) : AppColors.purple,
    surface: dark ? const Color(0xFF1A1730) : Colors.white,
  );
  final background = dark ? const Color(0xFF0F0D1A) : const Color(0xFFF4F2FD);
  final fill = dark ? const Color(0xFF241F42) : const Color(0xFFEFECFB);

  OutlineInputBorder border(Color color, [double width = 0]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: width == 0
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: dark ? const Color(0xFF2C2750) : const Color(0xFFE6E1F8),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(scheme.primary, 1.6),
      errorBorder: border(scheme.error, 1.2),
      focusedErrorBorder: border(scheme.error, 1.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: dark ? const Color(0xFF1A1033) : Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(
        color: dark ? const Color(0xFF2C2750) : const Color(0xFFDCD5F6),
      ),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary.withValues(alpha: 0.2),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      height: 68,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(space: 1, thickness: 0.6),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    ),
  );
}
