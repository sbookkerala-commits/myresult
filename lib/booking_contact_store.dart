import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database/local_database.dart';

/// Booking WhatsApp phone shown on the result page title bar.
class BookingContactStore {
  static const _prefsKey = 'booking_whatsapp_phone_v1';

  static final ValueNotifier<String> whatsappPhone = ValueNotifier<String>('');

  static Future<void> init() async {
    final raw = await LocalDatabase.getString(_prefsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      whatsappPhone.value = raw.trim();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_prefsKey);
    if (legacy != null && legacy.trim().isNotEmpty) {
      whatsappPhone.value = legacy.trim();
    }
  }

  static Future<void> setWhatsappPhone(String phone) async {
    final cleaned = phone.trim();
    whatsappPhone.value = cleaned;
    await LocalDatabase.setString(_prefsKey, cleaned);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, cleaned);
  }
}
