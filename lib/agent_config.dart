import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database/local_database.dart';

/// Named price list / rate set (Group 1 = A/B/C, Group 2 = AB/BC/AC, Group 3 = SUPER/BOX).
class RateSet {
  final String id;
  final String name;
  final double group1Rate;
  final double group2Rate;
  final double group3Rate;

  const RateSet({
    required this.id,
    required this.name,
    required this.group1Rate,
    required this.group2Rate,
    required this.group3Rate,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'group1Rate': group1Rate,
        'group2Rate': group2Rate,
        'group3Rate': group3Rate,
      };

  static RateSet? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    double readRate(dynamic v, double fallback) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? fallback;
    }
    return RateSet(
      id: id,
      name: name,
      group1Rate: readRate(json['group1Rate'], 12),
      group2Rate: readRate(json['group2Rate'], 10),
      group3Rate: readRate(json['group3Rate'], 10),
    );
  }

  /// Same suffix rules as legacy booking logic.
  double rateForTicketType(String type) {
    final suffix = type.split('-').last.toUpperCase();
    if (suffix == 'A' || suffix == 'B' || suffix == 'C') return group1Rate;
    if (suffix == 'AB' || suffix == 'BC' || suffix == 'AC') return group2Rate;
    if (suffix == 'SUPER' || suffix == 'BOX') return group3Rate;
    return group3Rate;
  }
}

class RateSetStore {
  static const _prefsKey = 'rate_sets_v1';

  static final ValueNotifier<List<RateSet>> sets = ValueNotifier<List<RateSet>>([
    const RateSet(
      id: 'standard',
      name: 'Standard Rate',
      group1Rate: 12,
      group2Rate: 10,
      group3Rate: 10,
    ),
    const RateSet(
      id: 'economy',
      name: 'Economy Rate',
      group1Rate: 10,
      group2Rate: 8,
      group3Rate: 8,
    ),
  ]);

  static Future<void> init() async {
    final raw = await LocalDatabase.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final loaded = <RateSet>[];
      for (final item in decoded) {
        final s = RateSet.fromJson(Map<String, dynamic>.from(item as Map));
        if (s != null) loaded.add(s);
      }
      if (loaded.isNotEmpty) sets.value = loaded;
    } catch (e) {
      debugPrint('RateSetStore load error: $e');
    }
  }

  static Future<void> saveNow() async {
    final payload = jsonEncode(sets.value.map((s) => s.toJson()).toList());
    await LocalDatabase.setString(_prefsKey, payload);
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, payload);
  }

  static void replaceAll(List<dynamic> raw) {
    if (raw.isEmpty) return;
    final loaded = <RateSet>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final s = RateSet.fromJson(Map<String, dynamic>.from(item));
      if (s != null) loaded.add(s);
    }
    if (loaded.isNotEmpty) {
      sets.value = loaded;
      unawaited(saveNow());
    }
  }

  static RateSet? byId(String id) {
    final key = id.trim().toLowerCase();
    for (final s in sets.value) {
      if (s.id.toLowerCase() == key) return s;
    }
    return sets.value.isNotEmpty ? sets.value.first : null;
  }

  static String displayName(String id) => byId(id)?.name ?? id;

  static double rateFor(String rateSetId, String ticketType) {
    final set = byId(rateSetId);
    if (set != null) return set.rateForTicketType(ticketType);
    final suffix = ticketType.split('-').last.toUpperCase();
    if (suffix == 'A' || suffix == 'B' || suffix == 'C') return 12.0;
    return 10.0;
  }
}

/// Agent profile fields used for booking rate + limits.
class AgentProfile {
  final String scheme;
  final String rateSetId;
  final double amountLimit;
  final int digit1CountLimit;
  final int digit2CountLimit;
  final int digit3CountLimit;

  const AgentProfile({
    this.scheme = 'ALL',
    this.rateSetId = 'standard',
    this.amountLimit = 0,
    this.digit1CountLimit = 0,
    this.digit2CountLimit = 0,
    this.digit3CountLimit = 0,
  });

  Map<String, dynamic> toJson() => {
        'scheme': scheme,
        'rateSetId': rateSetId,
        'amountLimit': amountLimit,
        'digit1CountLimit': digit1CountLimit,
        'digit2CountLimit': digit2CountLimit,
        'digit3CountLimit': digit3CountLimit,
      };

  static AgentProfile fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AgentProfile();
    double readAmount(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }
    int readInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }
    return AgentProfile(
      scheme: json['scheme']?.toString() ?? 'ALL',
      rateSetId: json['rateSetId']?.toString() ?? 'standard',
      amountLimit: readAmount(json['amountLimit']),
      digit1CountLimit: readInt(json['digit1CountLimit']),
      digit2CountLimit: readInt(json['digit2CountLimit']),
      digit3CountLimit: readInt(json['digit3CountLimit']),
    );
  }

  bool get hasAmountLimit => amountLimit > 0;

  int digitLimitForMode(String selectedOption) {
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

class AgentRateResolver {
  static double rateForUsername(String username, String ticketType,
      {String? rateSetId}) {
    if (rateSetId != null && rateSetId.isNotEmpty) {
      return RateSetStore.rateFor(rateSetId, ticketType);
    }
    return RateSetStore.rateFor('standard', ticketType);
  }
}
