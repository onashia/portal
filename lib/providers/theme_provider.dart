import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/storage_keys.dart';
import '../utils/app_logger.dart';

class ThemeNotifier extends Notifier<ThemeMode> {
  // Pre-loaded theme (set before app starts)
  static ThemeMode _initialTheme = ThemeMode.system;

  /// Set initial theme before provider builds
  static void setInitialTheme(ThemeMode mode) {
    _initialTheme = mode;
  }

  @override
  ThemeMode build() {
    return _initialTheme;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(StorageKeys.themeMode, mode.name);
    } catch (e) {
      AppLogger.error('Error saving theme', subCategory: 'theme', error: e);
    }
  }

  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setThemeMode(newMode);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);
