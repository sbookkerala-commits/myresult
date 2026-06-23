import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database/local_database.dart';

class DigitCountLimits {
  final int digit3CountLimit;
  final int digit2CountLimit;
  final int digit1CountLimit;

  const DigitCountLimits({
    this.digit3CountLimit = 0,
    this.digit2CountLimit = 0,
    this.digit1CountLimit = 0,
  });

  Map<String, dynamic> toJson() => {
        'digit3CountLimit': digit3CountLimit,
        'digit2CountLimit': digit2CountLimit,
        'digit1CountLimit': digit1CountLimit,
      };

  static DigitCountLimits fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DigitCountLimits();
    int read(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }
    return DigitCountLimits(
      digit3CountLimit: read(json['digit3CountLimit']),
      digit2CountLimit: read(json['digit2CountLimit']),
      digit1CountLimit: read(json['digit1CountLimit']),
    );
  }

  DigitCountLimits copyWith({
    int? digit3CountLimit,
    int? digit2CountLimit,
    int? digit1CountLimit,
  }) {
    return DigitCountLimits(
      digit3CountLimit: digit3CountLimit ?? this.digit3CountLimit,
      digit2CountLimit: digit2CountLimit ?? this.digit2CountLimit,
      digit1CountLimit: digit1CountLimit ?? this.digit1CountLimit,
    );
  }

  int limitForMode(String selectedOption) {
    switch (selectedOption) {
      case '1':
        return digit1CountLimit;
      case '2':
        return digit2CountLimit;
      case '3':
        return digit3CountLimit;
      default:
        return 0;
    }
  }
}

class DigitLimitStore {
  static const _prefsKey = 'global_digit_limits_v1';

  static final ValueNotifier<DigitCountLimits> limits =
      ValueNotifier<DigitCountLimits>(const DigitCountLimits());

  static Future<void> init() async {
    final raw = await LocalDatabase.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        limits.value = DigitCountLimits.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (e) {
      debugPrint('DigitLimitStore load error: $e');
    }
  }

  static Future<void> saveNow() async {
    final payload = jsonEncode(limits.value.toJson());
    await LocalDatabase.setString(_prefsKey, payload);
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, payload);
  }

  static void replaceFromCloud(Map<String, dynamic> raw) {
    if (raw.isEmpty) return;
    limits.value = DigitCountLimits.fromJson(raw);
    unawaited(saveNow());
  }

  static Future<void> update(DigitCountLimits next) async {
    limits.value = next;
    await saveNow();
  }

  /// Per-user limit wins when > 0; otherwise global limit applies.
  static int effectiveLimitForMode({
    required String selectedOption,
    required int userDigit1,
    required int userDigit2,
    required int userDigit3,
  }) {
    final userLimit = switch (selectedOption) {
      '1' => userDigit1,
      '2' => userDigit2,
      '3' => userDigit3,
      _ => 0,
    };
    if (userLimit > 0) return userLimit;
    return limits.value.limitForMode(selectedOption);
  }
}
