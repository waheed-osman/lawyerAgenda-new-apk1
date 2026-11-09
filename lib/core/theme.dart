import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      switch (p.getString('theme')) {
        case 'light':
          themeMode.value = ThemeMode.light;
          break;
        case 'dark':
          themeMode.value = ThemeMode.dark;
          break;
        default:
          themeMode.value = ThemeMode.system;
      }
    } catch (_) {}
  }

  static Future<void> setTheme(ThemeMode m) async {
    themeMode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system');
  }
}

class AppTheme {
  static const _seed = Color(0xFF1F3A5F);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: b);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: b == Brightness.dark ? const Color(0xFF10151C) : const Color(0xFFF5F6F8),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: b == Brightness.dark ? const Color(0xFF10151C) : const Color(0xFFF5F6F8),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static ThemeData light = _build(Brightness.light);
  static ThemeData dark = _build(Brightness.dark);
}
