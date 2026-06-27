import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage { en, ml, ta }

/// App UI language — persisted locally, shared by all users on device.
class AppLocale {
  AppLocale._();

  static const _prefsKey = 'app_language_v1';

  static final ValueNotifier<AppLanguage> language =
      ValueNotifier<AppLanguage>(AppLanguage.en);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    language.value = _parse(raw) ?? AppLanguage.en;
  }

  static Future<void> setLanguage(AppLanguage next) async {
    if (language.value == next) return;
    language.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next.name);
  }

  static AppLanguage? _parse(String? raw) {
    switch (raw) {
      case 'en':
        return AppLanguage.en;
      case 'ml':
        return AppLanguage.ml;
      case 'ta':
        return AppLanguage.ta;
      default:
        return null;
    }
  }

  static String nativeLabel(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.en:
        return 'English';
      case AppLanguage.ml:
        return 'മലയാളം';
      case AppLanguage.ta:
        return 'தமிழ்';
    }
  }
}
