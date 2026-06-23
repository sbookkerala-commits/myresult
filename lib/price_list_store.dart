import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent_config.dart';
import 'database/local_database.dart';

/// Base DEAR1 template — 8 schemes. Other draws swap prefix only.
const List<Map<String, dynamic>> kPriceListSchemesBase = [
  {
    'name': 'DEAR1-SUPER',
    'group': 'Group 3',
    'rate': 10,
    'rows': [
      [1, 1, 5000, 0],
      [2, 1, 500, 0],
      [3, 1, 250, 0],
      [4, 1, 100, 0],
      [5, 1, 50, 0],
      [6, 30, 20, 0],
    ],
  },
  {
    'name': 'DEAR1-BOX',
    'group': 'Group 3',
    'rate': 10,
    'rows': [
      [1, 1, 3000, 300],
      [2, 1, 800, 30],
      [3, 1, 800, 30],
      [4, 1, 800, 30],
      [5, 1, 800, 30],
      [6, 1, 800, 30],
      [1, 1, 3800, 330],
      [1, 1, 1600, 60],
    ],
  },
  {
    'name': 'DEAR1-A',
    'group': 'Group 1',
    'rate': 12,
    'rows': [
      [1, 1, 100, 0],
    ],
  },
  {
    'name': 'DEAR1-B',
    'group': 'Group 1',
    'rate': 12,
    'rows': [
      [1, 1, 100, 0],
    ],
  },
  {
    'name': 'DEAR1-C',
    'group': 'Group 1',
    'rate': 12,
    'rows': [
      [1, 1, 100, 0],
    ],
  },
  {
    'name': 'DEAR1-AB',
    'group': 'Group 2',
    'rate': 10,
    'rows': [
      [1, 1, 700, 0],
    ],
  },
  {
    'name': 'DEAR1-BC',
    'group': 'Group 2',
    'rate': 10,
    'rows': [
      [1, 1, 700, 0],
    ],
  },
  {
    'name': 'DEAR1-AC',
    'group': 'Group 2',
    'rate': 10,
    'rows': [
      [1, 1, 700, 0],
    ],
  },
];

const List<String> kDrawTimesForRateMaster = [
  'DEAR 1 PM',
  'LSK 3 PM',
  'DEAR 6 PM',
  'DEAR 8 PM',
];

const List<String> kAllDrawPrefixes = ['DEAR1', 'LSK3', 'DEAR6', 'DEAR8'];

String schemeSuffixFromName(String name) {
  final parts = name.split('-');
  if (parts.length < 2) return name.toUpperCase();
  return parts.sublist(1).join('-').toUpperCase();
}

String schemeNameWithPrefix(String prefix, String suffix) {
  return '${prefix.toUpperCase()}-${suffix.toUpperCase()}';
}

List<Map<String, dynamic>> applyDrawPrefixToSchemes(
  List<Map<String, dynamic>> source,
  String drawPrefix,
) {
  final p = drawPrefix.toUpperCase();
  return source.map((s) {
    final suffix = schemeSuffixFromName(s['name']?.toString() ?? '');
    return {
      'name': schemeNameWithPrefix(p, suffix),
      'group': s['group']?.toString() ?? '',
      'rate': coerceSchemeRate(s['rate'], schemeNameWithPrefix(p, suffix)),
      'rows': coercePrizeRows(s['rows']),
    };
  }).toList();
}

const Map<int, double> kBillingSchemeMultipliers = {
  1: 1.0,
  2: 0.75,
  3: 0.50,
  4: 0.25,
};

String priceListDrawPrefixForTime(String drawTime) {
  switch (drawTime.trim().toUpperCase()) {
    case 'LSK 3 PM':
      return 'LSK3';
    case 'DEAR 6 PM':
      return 'DEAR6';
    case 'DEAR 8 PM':
      return 'DEAR8';
    case 'DEAR 1 PM':
    default:
      return 'DEAR1';
  }
}

String drawTimeFromType(String type) {
  final t = type.toUpperCase();
  if (t.startsWith('LSK3')) return 'LSK 3 PM';
  if (t.startsWith('DEAR6')) return 'DEAR 6 PM';
  if (t.startsWith('DEAR8')) return 'DEAR 8 PM';
  return 'DEAR 1 PM';
}

int schemeGroupFromType(String type) {
  final suffix = type.split('-').last.toUpperCase();
  if (suffix == 'A' || suffix == 'B' || suffix == 'C') return 1;
  if (suffix == 'AB' || suffix == 'BC' || suffix == 'AC') return 2;
  if (suffix == 'SUPER' || suffix == 'BOX' || suffix == 'DC') return 3;
  return 3;
}

String schemeNameFromType(String type) {
  final parts = type.split('-');
  if (parts.length < 2) return type.toUpperCase();
  return '${parts[0].toUpperCase()}-${parts.last.toUpperCase()}';
}

double defaultRateForGroup(int group) {
  switch (group) {
    case 1:
      return 12.0;
    case 2:
      return 10.0;
    default:
      return 10.0;
  }
}

double getRetailRate(String type) {
  final suffix = type.split('-').last.toUpperCase();
  if (suffix == 'A' || suffix == 'B' || suffix == 'C') return 12.0;
  return 10.0;
}

int coerceCellInt(dynamic v, {int fallback = 0}) {
  if (v is bool) return v ? 1 : 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? fallback;
}

double coerceSchemeRate(dynamic v, String schemeName) {
  if (v is bool) {
    return defaultRateForGroup(schemeGroupFromType(schemeName));
  }
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString().trim() ?? '') ??
      defaultRateForGroup(schemeGroupFromType(schemeName));
}

/// Booking/sales rate — always double, never truncated to int.
double readBookingRate(dynamic v) {
  if (v == null) return 0;
  if (v is bool) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString().trim() ?? '') ?? 0;
}

/// Line amount before billing-scheme multiplier: rate × count (no rounding).
double bookingAmountFromRate(double rate, int count) {
  if (count <= 0 || rate <= 0) return 0;
  return rate * count;
}

List<List<int>> coercePrizeRows(dynamic rowsRaw) {
  if (rowsRaw is! List) return [];
  final rows = <List<int>>[];
  for (final row in rowsRaw) {
    if (row is! List) continue;
    rows.add([
      coerceCellInt(row.isNotEmpty ? row[0] : 0, fallback: 1),
      coerceCellInt(row.length > 1 ? row[1] : 1, fallback: 1),
      coerceCellInt(row.length > 2 ? row[2] : 0),
      coerceCellInt(row.length > 3 ? row[3] : 0),
    ]);
  }
  return rows;
}

/// Per-user game rates + superDcRate (Rate Master fields).
class UserGameRates {
  double superDcRate;
  double rateDear1D1;
  double rateDear1D2;
  double rateDear1D3;
  double rateLsk3D1;
  double rateLsk3D2;
  double rateLsk3D3;
  double rateDear6D1;
  double rateDear6D2;
  double rateDear6D3;
  double rateDear8D1;
  double rateDear8D2;
  double rateDear8D3;
  int billingScheme;

  UserGameRates({
    this.superDcRate = 0,
    this.rateDear1D1 = 0,
    this.rateDear1D2 = 0,
    this.rateDear1D3 = 0,
    this.rateLsk3D1 = 0,
    this.rateLsk3D2 = 0,
    this.rateLsk3D3 = 0,
    this.rateDear6D1 = 0,
    this.rateDear6D2 = 0,
    this.rateDear6D3 = 0,
    this.rateDear8D1 = 0,
    this.rateDear8D2 = 0,
    this.rateDear8D3 = 0,
    this.billingScheme = 1,
  });

  Map<String, dynamic> toJson() => {
        'superDcRate': superDcRate,
        'rateDear1D1': rateDear1D1,
        'rateDear1D2': rateDear1D2,
        'rateDear1D3': rateDear1D3,
        'rateLsk3D1': rateLsk3D1,
        'rateLsk3D2': rateLsk3D2,
        'rateLsk3D3': rateLsk3D3,
        'rateDear6D1': rateDear6D1,
        'rateDear6D2': rateDear6D2,
        'rateDear6D3': rateDear6D3,
        'rateDear8D1': rateDear8D1,
        'rateDear8D2': rateDear8D2,
        'rateDear8D3': rateDear8D3,
        'billingScheme': billingScheme,
      };

  static UserGameRates fromJson(Map<String, dynamic>? json) {
    if (json == null) return UserGameRates();
    double read(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }
    int readInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 1;
    }
    return UserGameRates(
      superDcRate: read(json['superDcRate']),
      rateDear1D1: read(json['rateDear1D1']),
      rateDear1D2: read(json['rateDear1D2']),
      rateDear1D3: read(json['rateDear1D3']),
      rateLsk3D1: read(json['rateLsk3D1']),
      rateLsk3D2: read(json['rateLsk3D2']),
      rateLsk3D3: read(json['rateLsk3D3']),
      rateDear6D1: read(json['rateDear6D1']),
      rateDear6D2: read(json['rateDear6D2']),
      rateDear6D3: read(json['rateDear6D3']),
      rateDear8D1: read(json['rateDear8D1']),
      rateDear8D2: read(json['rateDear8D2']),
      rateDear8D3: read(json['rateDear8D3']),
      billingScheme: readInt(json['billingScheme']).clamp(1, 4),
    );
  }

  /// DEAR1 template values shown in unified Rate Master editor.
  double get unifiedD1 => rateDear1D1;
  double get unifiedD2 => rateDear1D2;
  double get unifiedD3 => rateDear1D3;

  /// Apply same 1D/2D/3D rates to all four draws.
  UserGameRates withUnifiedRates({
    double? superDcRate,
    double? d1,
    double? d2,
    double? d3,
    int? billingScheme,
  }) {
    final u1 = d1 ?? rateDear1D1;
    final u2 = d2 ?? rateDear1D2;
    final u3 = d3 ?? rateDear1D3;
    return UserGameRates(
      superDcRate: superDcRate ?? this.superDcRate,
      rateDear1D1: u1,
      rateDear1D2: u2,
      rateDear1D3: u3,
      rateLsk3D1: u1,
      rateLsk3D2: u2,
      rateLsk3D3: u3,
      rateDear6D1: u1,
      rateDear6D2: u2,
      rateDear6D3: u3,
      rateDear8D1: u1,
      rateDear8D2: u2,
      rateDear8D3: u3,
      billingScheme: billingScheme ?? this.billingScheme,
    );
  }

  double rateForDrawGroup(String drawPrefix, int group) {
    final p = drawPrefix.toUpperCase();
    switch (p) {
      case 'LSK3':
        if (group == 1) return rateLsk3D1;
        if (group == 2) return rateLsk3D2;
        return rateLsk3D3;
      case 'DEAR6':
        if (group == 1) return rateDear6D1;
        if (group == 2) return rateDear6D2;
        return rateDear6D3;
      case 'DEAR8':
        if (group == 1) return rateDear8D1;
        if (group == 2) return rateDear8D2;
        return rateDear8D3;
      case 'DEAR1':
      default:
        if (group == 1) return rateDear1D1;
        if (group == 2) return rateDear1D2;
        return rateDear1D3;
    }
  }
}

class PriceListStore {
  static const _prefsKey = 'app_pricelist_schemes_v1';
  static const _gameRatesKey = 'app_pricelist_game_rates_v1';

  static final Map<String, List<Map<String, dynamic>>> _schemesByKey = {};
  static final Map<String, UserGameRates> _gameRatesByUser = {};

  static Future<void> init() async {
    await _loadSchemes();
    await _loadGameRates();
  }

  static String _normUser(String username) =>
      username.trim().toLowerCase();

  /// dear1 → `user`, others → `user::lsk3` etc.
  static String storageKey(String username, String drawPrefix) {
    final u = _normUser(username);
    final p = drawPrefix.trim().toUpperCase();
    if (p == 'DEAR1') return u;
    return '$u::${p.toLowerCase()}';
  }

  static List<Map<String, dynamic>> _baseForPrefix(String drawPrefix) {
    final prefix = drawPrefix.toUpperCase();
    return kPriceListSchemesBase
        .map(
          (s) {
            final name = s['name'].toString().replaceFirst('DEAR1', prefix);
            return {
              'name': name,
              'group': s['group'],
              'rate': coerceSchemeRate(s['rate'], name),
              'rows': (s['rows'] as List)
                  .map((r) =>
                      List<int>.from((r as List).cast<num>().map((e) => e.toInt())))
                  .toList(),
            };
          },
        )
        .toList();
  }

  static List<Map<String, dynamic>> _coerceFromJson(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final name = m['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final rows = coercePrizeRows(m['rows']);
      out.add({
        'name': name,
        'group': m['group']?.toString() ?? '',
        'rate': coerceSchemeRate(m['rate'], name),
        'rows': rows,
      });
    }
    return out;
  }

  static Future<void> _loadSchemes() async {
    final raw = await LocalDatabase.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _schemesByKey.clear();
      decoded.forEach((key, value) {
        final list = _coerceFromJson(value);
        if (list.isNotEmpty) {
          _schemesByKey[key.toString()] = list;
        }
      });
    } catch (e) {
      debugPrint('PriceListStore load schemes error: $e');
    }
  }

  static Future<void> _loadGameRates() async {
    final raw = await LocalDatabase.getString(_gameRatesKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _gameRatesByUser.clear();
      decoded.forEach((key, value) {
        if (value is Map) {
          _gameRatesByUser[key.toString()] =
              UserGameRates.fromJson(Map<String, dynamic>.from(value));
        }
      });
    } catch (e) {
      debugPrint('PriceListStore load game rates error: $e');
    }
  }

  static Future<void> _persistSchemes() async {
    final payload = jsonEncode(_schemesByKey);
    await LocalDatabase.setString(_prefsKey, payload);
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, payload);
  }

  static Future<void> _persistGameRates() async {
    final map = <String, dynamic>{};
    _gameRatesByUser.forEach((k, v) => map[k] = v.toJson());
    final payload = jsonEncode(map);
    await LocalDatabase.setString(_gameRatesKey, payload);
    final p = await SharedPreferences.getInstance();
    await p.setString(_gameRatesKey, payload);
  }

  static void replaceAllFromCloud(Map<String, dynamic>? cloudMap) {
    if (cloudMap == null || cloudMap.isEmpty) return;
    cloudMap.forEach((key, value) {
      final list = _coerceFromJson(value);
      if (list.isNotEmpty) {
        _schemesByKey[key.toString()] = list;
      }
    });
    unawaited(_persistSchemes());
  }

  static void replaceGameRatesFromCloud(Map<String, dynamic>? cloudMap) {
    if (cloudMap == null || cloudMap.isEmpty) return;
    cloudMap.forEach((key, value) {
      if (value is Map) {
        _gameRatesByUser[key.toString()] =
            UserGameRates.fromJson(Map<String, dynamic>.from(value));
      }
    });
    unawaited(_persistGameRates());
  }

  static Map<String, dynamic> exportAllSchemes() =>
      Map<String, dynamic>.from(_schemesByKey);

  static Map<String, dynamic> exportAllGameRates() {
    final map = <String, dynamic>{};
    _gameRatesByUser.forEach((k, v) => map[k] = v.toJson());
    return map;
  }

  static List<Map<String, dynamic>> getSchemesForUserDraw(
    String username,
    String drawPrefix,
  ) {
    final p = drawPrefix.trim().toUpperCase();
    final canonicalKey = storageKey(username, 'DEAR1');
    final canonical = _schemesByKey[canonicalKey];
    if (canonical != null && canonical.isNotEmpty) {
      if (p == 'DEAR1') {
        return canonical.map((s) => Map<String, dynamic>.from(s)).toList();
      }
      return applyDrawPrefixToSchemes(canonical, p);
    }

    final key = storageKey(username, drawPrefix);
    final stored = _schemesByKey[key];
    if (stored != null && stored.isNotEmpty) {
      return stored.map((s) => Map<String, dynamic>.from(s)).toList();
    }
    return _baseForPrefix(drawPrefix);
  }

  /// Canonical DEAR1 template used for editing — applies to all draws on save.
  static List<Map<String, dynamic>> getUnifiedSchemesForUser(String username) {
    return getSchemesForUserDraw(username, 'DEAR1').map((s) {
      final name = s['name']?.toString().toUpperCase() ?? '';
      if (name.endsWith('-BOX')) {
        return _ensureBoxSchemeRows(s);
      }
      return Map<String, dynamic>.from(s);
    }).toList();
  }

  static List<Map<String, dynamic>> _normalizeSchemesToDear1(
    List<Map<String, dynamic>> data,
  ) {
    return applyDrawPrefixToSchemes(_coerceFromJson(data), 'DEAR1');
  }

  static Map<String, dynamic>? _schemeByName(
    String username,
    String schemeName,
    String drawPrefix,
  ) {
    final target = schemeName.toUpperCase();
    for (final s in getSchemesForUserDraw(username, drawPrefix)) {
      if (s['name']?.toString().toUpperCase() == target) return s;
    }
    return null;
  }

  static double _baseDefaultRate(String schemeName) {
    final group = schemeGroupFromType(schemeName);
    return defaultRateForGroup(group);
  }

  static double rateForUserType(
    String username,
    String type, {
    bool onlyCustom = false,
  }) {
    final drawPrefix = priceListDrawPrefixForTime(drawTimeFromType(type));
    final schemeName = schemeNameFromType(type);
    final scheme = _schemeByName(username, schemeName, drawPrefix);
    if (scheme == null) return _baseDefaultRate(schemeName);
    final rate = coerceSchemeRate(scheme['rate'], schemeName);
    if (onlyCustom) {
      final base = _baseDefaultRate(schemeName);
      if ((rate - base).abs() < 0.001) return 0;
    }
    return rate;
  }

  static UserGameRates gameRatesFor(String username) {
    final key = _normUser(username);
    return _gameRatesByUser[key] ?? UserGameRates();
  }

  static Future<void> setGameRatesForUser(
    String username,
    UserGameRates rates,
  ) async {
    _gameRatesByUser[_normUser(username)] = rates;
    await _persistGameRates();
  }

  static Future<void> setUnifiedGameRatesForUser(
    String username, {
    required double superDcRate,
    required double d1,
    required double d2,
    required double d3,
    required int billingScheme,
  }) async {
    final base = gameRatesFor(username);
    await setGameRatesForUser(
      username,
      base.withUnifiedRates(
        superDcRate: superDcRate,
        d1: d1,
        d2: d2,
        d3: d3,
        billingScheme: billingScheme,
      ),
    );
  }

  static Future<void> setSchemesForAllDrawsNow(
    String username,
    List<Map<String, dynamic>> data,
  ) async {
    final canonical = _normalizeSchemesToDear1(data);
    _schemesByKey[storageKey(username, 'DEAR1')] = canonical;
    for (final prefix in kAllDrawPrefixes) {
      if (prefix == 'DEAR1') continue;
      _schemesByKey[storageKey(username, prefix)] =
          applyDrawPrefixToSchemes(canonical, prefix);
    }
    await _persistSchemes();
  }

  static Future<void> setSchemesForUserDrawNow(
    String username,
    String drawPrefix,
    List<Map<String, dynamic>> data,
  ) async {
    await setSchemesForAllDrawsNow(username, data);
  }

  static Map<String, dynamic>? schemeForType(String username, String type) {
    final drawPrefix = priceListDrawPrefixForTime(drawTimeFromType(type));
    return _schemeByName(username, schemeNameFromType(type), drawPrefix);
  }

  /// Winning lookup always uses DEAR1 template (unified price list).
  static Map<String, dynamic>? dear1SchemeBySuffix(
    String username,
    String suffix,
  ) {
    final target = schemeNameWithPrefix('DEAR1', suffix).toUpperCase();
    Map<String, dynamic>? scheme;
    for (final s in getUnifiedSchemesForUser(username)) {
      if (s['name']?.toString().toUpperCase() == target) {
        scheme = s;
        break;
      }
    }
    scheme ??= () {
      for (final s in _baseForPrefix('DEAR1')) {
        if (s['name']?.toString().toUpperCase() == target) return s;
      }
      return null;
    }();
    if (scheme == null) return null;
    if (suffix.toUpperCase() == 'BOX') {
      return _ensureBoxSchemeRows(scheme);
    }
    return scheme;
  }

  static const List<List<int>> kBoxSchemeDefaultRows = [
    [1, 1, 3000, 300],
    [2, 1, 800, 30],
    [3, 1, 800, 30],
    [4, 1, 800, 30],
    [5, 1, 800, 30],
    [6, 1, 800, 30],
    [1, 1, 3800, 330],
    [1, 1, 1600, 60],
  ];

  static Map<String, dynamic> _ensureBoxSchemeRows(
    Map<String, dynamic> scheme,
  ) {
    final copy = Map<String, dynamic>.from(scheme);
    final rows = coercePrizeRows(copy['rows']);
    while (rows.length < kBoxSchemeDefaultRows.length) {
      rows.add(List<int>.from(kBoxSchemeDefaultRows[rows.length]));
    }
    copy['rows'] = rows;
    return copy;
  }

  /// Winning unit prize from price list rows for matched rank (1-based position).
  static double prizeUnitFromRows({
    required String username,
    required String type,
    required int position,
    required bool isCompliment,
  }) {
    final scheme = schemeForType(username, type);
    if (scheme == null) return 0;
    final rows = scheme['rows'];
    if (rows is! List) return 0;
    for (final row in rows) {
      if (row is! List || row.length < 3) continue;
      final pos = coerceCellInt(row[0], fallback: 1);
      if (pos != position) continue;
      final amount = coerceCellInt(row[2]).toDouble();
      final superBonus =
          row.length > 3 ? coerceCellInt(row[3]).toDouble() : 0.0;
      return isCompliment ? superBonus : amount;
    }
    return 0;
  }
}

/// Effective sale rate priority chain for booking.
double effectiveSaleRateForUser({
  required String username,
  required String type,
  String? role,
  String? rateSetId,
}) {
  final suffix = type.split('-').last.toUpperCase();
  final group = schemeGroupFromType(type);
  final drawPrefix = priceListDrawPrefixForTime(drawTimeFromType(type));
  final gameRates = PriceListStore.gameRatesFor(username);
  final isAdmin = (role ?? '').toUpperCase() == 'ADMIN';

  // 1. SUPER / DC + superDcRate
  if ((suffix == 'SUPER' || suffix == 'DC') && gameRates.superDcRate > 0) {
    return gameRates.superDcRate;
  }

  // 2. Explicit per-draw game rates
  final explicit = gameRates.rateForDrawGroup(drawPrefix, group);
  if (explicit > 0) return explicit;

  // 3. Custom scheme rate (different from base default)
  final custom = PriceListStore.rateForUserType(username, type, onlyCustom: true);
  if (custom > 0) return custom;

  // Agent RateSet (backward compatible with existing agent assign)
  if (rateSetId != null && rateSetId.isNotEmpty) {
    return RateSetStore.rateFor(rateSetId, type);
  }

  // 4. Defaults by group
  if (isAdmin) return getRetailRate(type);
  return defaultRateForGroup(group);
}

double applyBillingSchemeAmount(double base, int billingScheme) {
  final mult = kBillingSchemeMultipliers[billingScheme.clamp(1, 4)] ?? 1.0;
  return base * mult;
}

double effectiveRowAmountForUser({
  required String username,
  required String type,
  required int count,
  String? role,
  String? rateSetId,
  int? billingScheme,
}) {
  if (count <= 0) return 0;
  final rate = effectiveSaleRateForUser(
    username: username,
    type: type,
    role: role,
    rateSetId: rateSetId,
  );
  final base = bookingAmountFromRate(rate, count);
  final scheme =
      billingScheme ?? PriceListStore.gameRatesFor(username).billingScheme;
  return applyBillingSchemeAmount(base, scheme);
}
