import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool _useSystemTheme = false;

  bool get isDarkMode => _isDarkMode;

  bool get useSystemTheme => _useSystemTheme;

  ThemeProvider() {
    loadFromPrefs();
  }

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _useSystemTheme = prefs.getBool('useSystemTheme') ?? false;

      if (_useSystemTheme) {
        _isDarkMode =
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark;
      } else {
        _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      }

      notifyListeners();
    } catch (e) {
      // Keep default settings if preferences cannot be loaded.
    }
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    _useSystemTheme = false;

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('isDarkMode', _isDarkMode);
      await prefs.setBool('useSystemTheme', false);
    } catch (e) {
      // Ignore preference save errors.
    }
  }

  Future<void> toggleDarkMode() async {
    await toggleTheme();
  }

  Future<void> toggleSystemTheme(bool value) async {
    _useSystemTheme = value;

    if (_useSystemTheme) {
      _isDarkMode =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark;
    }

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('useSystemTheme', _useSystemTheme);
      await prefs.setBool('isDarkMode', _isDarkMode);
    } catch (e) {
      // Ignore preference save errors.
    }
  }
}
