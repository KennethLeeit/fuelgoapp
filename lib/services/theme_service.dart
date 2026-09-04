import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the dark-mode preference, persists it (shared_preferences,
/// same pattern as VehiclePreferenceService), and notifies main.dart to
/// swap ThemeData when it changes.
class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _key = 'dark_mode_enabled';

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  /// Call once at app startup, before the first frame — see main.dart.
  Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Falls back to light mode if prefs aren't available for some reason.
    }
  }

  Future<void> setDarkMode(bool value) async {
    if (_isDarkMode == value) return;
    _isDarkMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Non-fatal — the toggle still works for this session even if it
      // couldn't be saved.
    }
  }

  Future<void> toggle() => setDarkMode(!_isDarkMode);
}
