import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_locale.dart';
import 'app_messages.dart';
import 'draw_schedule_store.dart';
import 'data_retention.dart';
import 'digit_limit_store.dart';
import 'agent_config.dart';
import 'booking_contact_store.dart';
import 'price_list_store.dart';
import 'config/api_config.dart';
import 'services/api_service.dart';
import 'kerala_compliment_rules.dart';
import 'result_page_template.dart';
import 'lottery_live_links.dart';
import 'services/dear_auto_result_service.dart';
import 'services/kerala_result_fetcher.dart';
import 'services/result_fetch_service.dart';
import 'services/sync_service.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'database/local_database.dart';
import 'whatsapp_booking_parser.dart';
import 'havells_shell_page.dart';

// Local SQLite cache (mobile) + SharedPreferences fallback (web)
class AppDatabase {
  static Future<void> ensureReady() async {
    await LocalDatabase.ensureReady();
  }

  static Future<String?> loadSalesJson() async =>
      kIsWeb ? LegacyPrefs.getString("db_sales") : LocalDatabase.getString("db_sales");
  static Future<String?> loadUsersJson() async =>
      kIsWeb ? LegacyPrefs.getString("db_users") : LocalDatabase.getString("db_users");
  static Future<String?> loadResultsJson() async =>
      kIsWeb ? LegacyPrefs.getString("db_results") : LocalDatabase.getString("db_results");

  static Future<void> replaceSales(List l) async {
    final json = jsonEncode(l);
    if (kIsWeb) {
      await LegacyPrefs.setString("db_sales", json);
    } else {
      await LocalDatabase.setString("db_sales", json);
    }
  }

  static Future<void> replaceUsers(List l) async {
    final json = jsonEncode(l);
    if (kIsWeb) {
      await LegacyPrefs.setString("db_users", json);
    } else {
      await LocalDatabase.setString("db_users", json);
    }
  }

  static Future<void> replaceResults(List l) async {
    final json = jsonEncode(l);
    if (kIsWeb) {
      await LegacyPrefs.setString("db_results", json);
    } else {
      await LocalDatabase.setString("db_results", json);
    }
  }

  static Future<void> replaceBills(List l) async {
    final json = jsonEncode(l);
    if (kIsWeb) {
      await LegacyPrefs.setString("db_bills", json);
    } else {
      await LocalDatabase.setString("db_bills", json);
    }
  }

  static Future<List<Map<String, dynamic>>> loadAllBillMaps() async {
    final s = kIsWeb
        ? await LegacyPrefs.getString("db_bills")
        : await LocalDatabase.getString("db_bills");
    if (s == null || s.isEmpty) return [];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint("Error loading bills: $e");
    }
    return [];
  }
}

// LegacyPrefs using SharedPreferences
class LegacyPrefs {
  static Future<String?> getString(String k) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(k);
  }

  static Future<void> setString(String k, String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(k, v);
  }
}

DateTime _calendarDate(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String formatBillDateTime(DateTime dt) {
  final local = dt.toLocal();
  final int hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String ampm = local.hour >= 12 ? "PM" : "AM";
  final d = local.day.toString().padLeft(2, "0");
  final m = local.month.toString().padLeft(2, "0");
  final y = local.year;
  return "$d/$m/$y $hour12:${local.minute.toString().padLeft(2, "0")} $ampm";
}

/// Default report date — real calendar today (IST). Not business/booking date.
DateTime defaultReportFromDate() => calendarTodayInIndia();

DateTime defaultReportToDate() => calendarTodayInIndia();

/// Sales Report default — calendar today in India (IST). Rolls only at IST midnight.
DateTime calendarTodayInIndia({DateTime? at}) {
  final ist = (at ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(ist.year, ist.month, ist.day);
}

DateTime defaultSalesReportDate() => calendarTodayInIndia();

String formatSalesAmount(double amount) => amount.toStringAsFixed(2);

bool billInDateRange(DateTime billTime, DateTime from, DateTime to) {
  final b = _calendarDate(billTime);
  final f = _calendarDate(from);
  final t = _calendarDate(to);
  return !b.isBefore(f) && !b.isAfter(t);
}

bool isSameBusinessDate(DateTime a, DateTime b) =>
    billInDateRange(a, b, b);

DateTime _resolveBookingBusinessDate({
  required DateTime createdAt,
  String? drawName,
  Iterable<Map<String, dynamic>>? rows,
  DateTime? parsedBusiness,
}) {
  if (parsedBusiness != null) {
    return _calendarDate(parsedBusiness.toLocal());
  }
  final draw = (drawName ?? '').trim();
  final effectiveDraw = draw.isNotEmpty
      ? draw
      : (rows != null && rows.isNotEmpty
          ? DrawScheduleStore.drawTimeFromRowType(
              rows.first['type'].toString(),
            )
          : '');
  if (effectiveDraw.isNotEmpty) {
    return DrawScheduleStore.businessDateForDraw(
      effectiveDraw,
      at: createdAt.toLocal(),
    );
  }
  return _calendarDate(createdAt);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  if (!kIsWeb) {
    await AppDatabase.ensureReady();
  }
  await Future.wait([
    AppLocale.init(),
    UserStore.init(),
    RateSetStore.init(),
    PriceListStore.init(),
    DrawScheduleStore.init(),
    DigitLimitStore.init(),
    BillsStore.init(),
    SalesStore.init(),
    ResultStore.init(),
    BookingContactStore.init(),
  ]);

  _scheduleDailyRetentionPurge();
  _startDearAutoResultScheduler();
  _startKeralaAutoResultScheduler();

  AppDrawTheme.setDraw(DrawScheduleStore.currentUiDraw());
  runApp(const MyApp());
  unawaited(_initNetworkServices());
}

Future<void> _initNetworkServices() async {
  try {
    await ApiConfig.init();
    await SyncService.init();
    unawaited(SyncService.flushQueue());
  } catch (e) {
    debugPrint('Network init error: $e');
  }
}

Timer? _retentionPurgeTimer;
Timer? _dearAutoFetchTimer;
Timer? _keralaAutoFetchTimer;

Future<void> _runDearAutoFetchTick() async {
  try {
    await ResultStore.refreshDearDrawsIfNeeded();
  } catch (e) {
    debugPrint('Dear auto fetch tick error: $e');
  }
}

Future<void> _runKeralaAutoFetchTick() async {
  try {
    await ResultStore.refreshKeralaIfNeeded();
  } catch (e) {
    debugPrint('Kerala auto fetch tick error: $e');
  }
}

void _startDearAutoResultScheduler() {
  _dearAutoFetchTimer?.cancel();
  unawaited(_runDearAutoFetchTick());
  _dearAutoFetchTimer = Timer.periodic(
    ResultFetchService.kTodayPollInterval,
    (_) => unawaited(_runDearAutoFetchTick()),
  );
}

void _startKeralaAutoResultScheduler() {
  _keralaAutoFetchTimer?.cancel();
  unawaited(_runKeralaAutoFetchTick());
  _keralaAutoFetchTimer = Timer.periodic(
    ResultFetchService.kTodayPollInterval,
    (_) => unawaited(_runKeralaAutoFetchTick()),
  );
}

Future<void> _runLocalRetentionPurge() async {
  final removed = await Future.wait([
    BillsStore.purgeExpired(),
    SalesStore.purgeExpired(),
    ResultStore.purgeExpired(),
  ]);
  final total = removed.fold<int>(0, (sum, n) => sum + n);
  if (total > 0) {
    debugPrint('Retention purge: $total records older than $kDataRetentionDays days');
  }
}

void _scheduleDailyRetentionPurge() {
  _retentionPurgeTimer?.cancel();
  _retentionPurgeTimer = Timer.periodic(const Duration(hours: 24), (_) {
    unawaited(_runLocalRetentionPurge());
  });
}

class SaleEntry {
  final String type;
  final String number;
  final int count;
  final double amount;
  final String time;
  final DateTime createdAt;
  final DateTime businessDate;

  const SaleEntry({
    required this.type,
    required this.number,
    required this.count,
    required this.amount,
    required this.time,
    required this.createdAt,
    required this.businessDate,
  });

  Map<String, dynamic> toJson() => {
        "type": type,
        "number": number,
        "count": count,
        "amount": amount,
        "time": time,
        "createdAt": createdAt.toUtc().toIso8601String(),
        "businessDate": _calendarDate(businessDate).toIso8601String(),
      };

  static SaleEntry? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final created = DateTime.tryParse(json["createdAt"]?.toString() ?? "");
    if (created == null) return null;
    final localCreated = created.toLocal();
    final parsedBusiness = DateTime.tryParse(
      json["businessDate"]?.toString() ?? json["salesDate"]?.toString() ?? "",
    );
    final businessDate = _resolveBookingBusinessDate(
      createdAt: localCreated,
      drawName: json["time"]?.toString(),
      parsedBusiness: parsedBusiness,
    );
    final amountRaw = json["amount"];
    final double amt = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw.toString()) ?? 0.0;
    final countRaw = json["count"];
    final int cnt =
        countRaw is int ? countRaw : int.tryParse(countRaw.toString()) ?? 0;
    return SaleEntry(
      type: json["type"]?.toString() ?? "",
      number: json["number"]?.toString() ?? "",
      count: cnt,
      amount: amt,
      time: json["time"]?.toString() ?? "",
      createdAt: localCreated,
      businessDate: businessDate,
    );
  }
}

class SalesStore {
  static const String _prefsKey = "app_sales_v1";

  static final ValueNotifier<List<SaleEntry>> sales =
      ValueNotifier<List<SaleEntry>>([]);

  static Timer? _saveDebounce;

  static Future<void> init() async {
    final String? raw = kIsWeb
        ? await LegacyPrefs.getString(_prefsKey)
        : await AppDatabase.loadSalesJson();

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = <SaleEntry>[];
          for (final item in decoded) {
            final e = SaleEntry.fromJson(Map<String, dynamic>.from(item));
            if (e != null) loaded.add(e);
          }
          sales.value = loaded;
        }
      } catch (e) {
        debugPrint("Local sales load error: $e");
      }
    }
    await purgeExpired();
  }

  static Future<int> purgeExpired({DateTime? at}) async {
    final cutoff = retentionCutoffDate(at: at);
    final kept = sales.value.where((e) {
      final day = DateTime(
        e.createdAt.year,
        e.createdAt.month,
        e.createdAt.day,
      );
      return !day.isBefore(cutoff);
    }).toList();
    final removed = sales.value.length - kept.length;
    if (removed > 0) {
      sales.value = kept;
      await saveNow();
      debugPrint('SalesStore retention: removed $removed sales');
    }
    return removed;
  }

  static void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(saveNow());
    });
  }

  static Future<void> saveNow() async {
    final payload = jsonEncode(sales.value.map((e) => e.toJson()).toList());
    if (kIsWeb) {
      await LegacyPrefs.setString(_prefsKey, payload);
    } else {
      await AppDatabase.replaceSales(
          sales.value.map((e) => e.toJson()).toList());
    }
  }

  static void add(SaleEntry entry) {
    sales.value = [entry, ...sales.value];
    _scheduleSave();
    unawaited(SyncService.queueSale(entry.toJson()));
  }
}

class AppSession {
  static String username = "admin";
  static String role = "ADMIN";
}

class AppUser {
  final String username;
  final String password;
  final String role;
  final bool isBlocked;
  final bool isSalesBlocked;
  final String scheme;
  final String rateSetId;
  final double amountLimit;
  final int digit1CountLimit;
  final int digit2CountLimit;
  final int digit3CountLimit;

  const AppUser({
    required this.username,
    required this.password,
    required this.role,
    this.isBlocked = false,
    this.isSalesBlocked = false,
    this.scheme = "ALL",
    this.rateSetId = "standard",
    this.amountLimit = 0,
    this.digit1CountLimit = 0,
    this.digit2CountLimit = 0,
    this.digit3CountLimit = 0,
  });

  bool get isAgentRole =>
      role == "AGENT" || role == "SUBAGENT";

  AgentProfile get agentProfile => AgentProfile(
        scheme: scheme,
        rateSetId: rateSetId,
        amountLimit: amountLimit,
        digit1CountLimit: digit1CountLimit,
        digit2CountLimit: digit2CountLimit,
        digit3CountLimit: digit3CountLimit,
      );

  AppUser copyWith({
    String? username,
    String? password,
    String? role,
    bool? isBlocked,
    bool? isSalesBlocked,
    String? scheme,
    String? rateSetId,
    double? amountLimit,
    int? digit1CountLimit,
    int? digit2CountLimit,
    int? digit3CountLimit,
  }) {
    return AppUser(
      username: username ?? this.username,
      password: password ?? this.password,
      role: role ?? this.role,
      isBlocked: isBlocked ?? this.isBlocked,
      isSalesBlocked: isSalesBlocked ?? this.isSalesBlocked,
      scheme: scheme ?? this.scheme,
      rateSetId: rateSetId ?? this.rateSetId,
      amountLimit: amountLimit ?? this.amountLimit,
      digit1CountLimit: digit1CountLimit ?? this.digit1CountLimit,
      digit2CountLimit: digit2CountLimit ?? this.digit2CountLimit,
      digit3CountLimit: digit3CountLimit ?? this.digit3CountLimit,
    );
  }

  Map<String, dynamic> toJson() => {
        "username": username,
        "password": password,
        "role": role,
        "isBlocked": isBlocked,
        "isSalesBlocked": isSalesBlocked,
        "scheme": scheme,
        "rateSetId": rateSetId,
        "amountLimit": amountLimit,
        "digit1CountLimit": digit1CountLimit,
        "digit2CountLimit": digit2CountLimit,
        "digit3CountLimit": digit3CountLimit,
      };

  static AppUser? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final username = json["username"]?.toString() ?? "";
    final password = json["password"]?.toString() ?? "";
    final role = (json["role"]?.toString() ?? "").trim().toUpperCase();
    final isBlocked = json["isBlocked"] == true;
    final isSalesBlocked = json["isSalesBlocked"] == true;
    if (username.trim().isEmpty || role.isEmpty) {
      return null;
    }
    final profile = AgentProfile.fromJson(json);
    return AppUser(
      username: username.trim(),
      password: password.trim(),
      role: role,
      isBlocked: isBlocked,
      isSalesBlocked: isSalesBlocked,
      scheme: profile.scheme,
      rateSetId: profile.rateSetId,
      amountLimit: profile.amountLimit,
      digit1CountLimit: profile.digit1CountLimit,
      digit2CountLimit: profile.digit2CountLimit,
      digit3CountLimit: profile.digit3CountLimit,
    );
  }

  static AppUser? fromCloudMap(
    Map<String, dynamic> json, {
    AppUser? existing,
  }) {
    final username = json['username']?.toString().trim() ?? '';
    final role = (json['role']?.toString() ?? '').trim().toUpperCase();
    if (username.isEmpty || role.isEmpty) return null;
    final profile = AgentProfile.fromJson(json);
    return AppUser(
      username: username,
      password: existing?.password ?? '',
      role: role,
      isBlocked: json['isBlocked'] == true,
      isSalesBlocked: json['isSalesBlocked'] == true,
      scheme: profile.scheme,
      rateSetId: profile.rateSetId,
      amountLimit: profile.amountLimit,
      digit1CountLimit: profile.digit1CountLimit,
      digit2CountLimit: profile.digit2CountLimit,
      digit3CountLimit: profile.digit3CountLimit,
    );
  }
}

class UserStore {
  static const String _prefsKey = "app_users_v1";

  static final ValueNotifier<List<AppUser>> users =
      ValueNotifier<List<AppUser>>([
    const AppUser(username: "admin", password: "1234", role: "ADMIN"),
  ]);

  static Timer? _saveDebounce;

  static List<AppUser> _parseUsersPayload(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final loaded = <AppUser>[];
      for (final item in decoded) {
        final u = AppUser.fromJson(Map<String, dynamic>.from(item as Map));
        if (u != null) loaded.add(u);
      }
      return loaded;
    } catch (e) {
      debugPrint('UserStore parse error: $e');
      return [];
    }
  }

  static void _absorbUsers(Map<String, AppUser> merged, List<AppUser> incoming) {
    for (final u in incoming) {
      final key = u.username.trim().toLowerCase();
      final prev = merged[key];
      if (prev == null) {
        merged[key] = u;
        continue;
      }
      merged[key] = prev.copyWith(
        password: u.password.isNotEmpty ? u.password : prev.password,
        role: u.role,
        isBlocked: u.isBlocked,
        isSalesBlocked: u.isSalesBlocked,
        scheme: u.scheme,
        rateSetId: u.rateSetId,
        amountLimit: u.amountLimit,
        digit1CountLimit: u.digit1CountLimit,
        digit2CountLimit: u.digit2CountLimit,
        digit3CountLimit: u.digit3CountLimit,
      );
    }
  }

  static Future<void> reloadFromDisk() async {
    final merged = <String, AppUser>{
      for (final u in users.value) u.username.trim().toLowerCase(): u,
    };

    if (kIsWeb) {
      _absorbUsers(merged, _parseUsersPayload(await LegacyPrefs.getString(_prefsKey)));
      _absorbUsers(merged, _parseUsersPayload(await LegacyPrefs.getString('db_users')));
    } else {
      _absorbUsers(merged, _parseUsersPayload(await LocalDatabase.getString('db_users')));
      _absorbUsers(merged, _parseUsersPayload(await LocalDatabase.getString(_prefsKey)));
    }

    if (merged.isNotEmpty) {
      users.value = merged.values.toList();
    }

    if (!users.value.any((x) => x.role == 'ADMIN')) {
      users.value = [
        ...users.value,
        const AppUser(username: 'admin', password: '1234', role: 'ADMIN'),
      ];
    }
  }

  static Future<void> pullUsersFromCloud() async {
    if (ApiService.token == null) return;
    if (AppSession.role != 'ADMIN' && AppSession.role != 'AGENT') return;
    try {
      final cloudRows = await ApiService.getUsers();
      if (cloudRows.isEmpty) return;

      final merged = <String, AppUser>{
        for (final u in users.value) u.username.trim().toLowerCase(): u,
      };

      for (final item in cloudRows) {
        final key = (item['username']?.toString() ?? '').trim().toLowerCase();
        if (key.isEmpty) continue;
        final existing = merged[key];
        final cloudUser = AppUser.fromCloudMap(item, existing: existing);
        if (cloudUser == null) continue;
        merged[key] = cloudUser;
      }

      users.value = merged.values.toList();
      await persistNow();
      debugPrint('UserStore cloud pull: ${users.value.length} users');
    } catch (e) {
      debugPrint('UserStore cloud pull failed: $e');
    }
  }

  static Future<void> init() async {
    await reloadFromDisk();
  }

  static void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(saveNow());
    });
  }

  static Future<void> saveNow() async {
    final list = users.value.map((u) => u.toJson()).toList();
    final payload = jsonEncode(list);
    if (kIsWeb) {
      await LegacyPrefs.setString(_prefsKey, payload);
    } else {
      await AppDatabase.replaceUsers(list);
      await LocalDatabase.setString(_prefsKey, payload);
    }
  }

  static Future<void> persistNow() async {
    _saveDebounce?.cancel();
    await saveNow();
  }

  static void _syncUsersCloud() {
    if (AppSession.role == 'ADMIN') {
      unawaited(SyncService.queueUsers(
        users.value.map((u) => u.toJson()).toList(),
      ));
      unawaited(SyncService.queueRateSets(
        RateSetStore.sets.value.map((s) => s.toJson()).toList(),
      ));
      unawaited(SyncService.queuePriceList(
        PriceListStore.exportAllSchemes(),
        PriceListStore.exportAllGameRates(),
      ));
    }
  }

  static int _indexOfUsername(String username) {
    final u = username.trim().toLowerCase();
    return users.value.indexWhere((x) => x.username.trim().toLowerCase() == u);
  }

  static AppUser? authenticate(String username, String password) {
    final u = username.trim().toLowerCase();
    for (final user in users.value) {
      if (user.username.trim().toLowerCase() == u &&
          user.password == password) {
        return user;
      }
    }
    return null;
  }

  static bool usernameExists(String username) {
    final u = username.trim().toLowerCase();
    return users.value.any((x) => x.username.trim().toLowerCase() == u);
  }

  static List<String> getAllowedRoles(String currentRole) {
    switch (currentRole.toUpperCase()) {
      case "ADMIN":
        return ["AGENT", "SUBAGENT", "CUSTOMER"];
      case "AGENT":
        return ["SUBAGENT", "CUSTOMER"];
      case "SUBAGENT":
        return ["CUSTOMER"];
      default:
        return [];
    }
  }

  static AppUser? byUsername(String username) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return null;
    return users.value[idx];
  }

  static bool addUser({
    required String username,
    required String password,
    required String role,
    String scheme = "ALL",
    String rateSetId = "standard",
    double amountLimit = 0,
    int digit1CountLimit = 0,
    int digit2CountLimit = 0,
    int digit3CountLimit = 0,
    bool isBlocked = false,
    bool isSalesBlocked = false,
  }) {
    final u = username.trim();
    final targetRole = role.trim().toUpperCase();
    if (u.isEmpty || password.trim().isEmpty) return false;
    if (usernameExists(u)) return false;

    // റോൾ അടിസ്ഥാനത്തിലുള്ള ആക്സസ് ചെക്ക്
    final allowedRoles = getAllowedRoles(AppSession.role);
    if (!allowedRoles.contains(targetRole)) {
      debugPrint(
          "Permission denied: ${AppSession.role} cannot create $targetRole");
      return false;
    }

    final newUser = AppUser(
      username: u,
      password: password.trim(),
      role: targetRole,
      isBlocked: isBlocked,
      isSalesBlocked: isSalesBlocked,
      scheme: scheme,
      rateSetId: rateSetId,
      amountLimit: amountLimit,
      digit1CountLimit: digit1CountLimit,
      digit2CountLimit: digit2CountLimit,
      digit3CountLimit: digit3CountLimit,
    );
    users.value = [newUser, ...users.value];
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool updateRole({
    required String username,
    required String newRole,
  }) {
    final role = newRole.trim().toUpperCase();
    if (role.isEmpty) return false;

    final idx = _indexOfUsername(username);
    if (idx < 0) return false;

    final current = users.value[idx];
    final isSelf = current.username.trim().toLowerCase() ==
        AppSession.username.trim().toLowerCase();

    // Don't let the logged-in admin demote themselves by mistake.
    if (isSelf &&
        AppSession.role == "ADMIN" &&
        current.role == "ADMIN" &&
        role != "ADMIN") {
      return false;
    }

    // Always keep at least one ADMIN account in the database.
    if (current.role == "ADMIN" && role != "ADMIN") {
      final otherAdmins = users.value
          .where((x) => x.role == "ADMIN" && x.username != current.username)
          .length;
      if (otherAdmins <= 0) return false;
    }

    final next = List<AppUser>.from(users.value);
    next[idx] = current.copyWith(role: role);
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool setPassword(
      {required String username, required String newPassword}) {
    final pw = newPassword.trim();
    if (pw.isEmpty) return false;
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;
    final current = users.value[idx];
    final next = List<AppUser>.from(users.value);
    next[idx] = current.copyWith(password: pw);
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool isSalesBlocked(String username) =>
      byUsername(username)?.isSalesBlocked ?? false;

  static bool toggleLoginBlock(String username) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;
    final current = users.value[idx];
    final next = List<AppUser>.from(users.value);
    next[idx] = current.copyWith(isBlocked: !current.isBlocked);
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool toggleSalesBlock(String username) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;
    final current = users.value[idx];
    final next = List<AppUser>.from(users.value);
    next[idx] = current.copyWith(isSalesBlocked: !current.isSalesBlocked);
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool setAccessFlags({
    required String username,
    required bool loginBlocked,
    required bool salesBlocked,
  }) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;
    final current = users.value[idx];
    final next = List<AppUser>.from(users.value);
    next[idx] = current.copyWith(
      isBlocked: loginBlocked,
      isSalesBlocked: salesBlocked,
    );
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool updateAgentSettings({
    required String username,
    String? scheme,
    String? rateSetId,
    double? amountLimit,
    int? digit1CountLimit,
    int? digit2CountLimit,
    int? digit3CountLimit,
  }) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;
    final current = users.value[idx];
    if (!current.isAgentRole) return false;
    final next = List<AppUser>.from(users.value);
    next[idx] = current.copyWith(
      scheme: scheme,
      rateSetId: rateSetId,
      amountLimit: amountLimit,
      digit1CountLimit: digit1CountLimit,
      digit2CountLimit: digit2CountLimit,
      digit3CountLimit: digit3CountLimit,
    );
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool updateUserLimits({
    required String username,
    double? amountLimit,
    int? digit1CountLimit,
    int? digit2CountLimit,
    int? digit3CountLimit,
  }) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;
    final current = users.value[idx];
    if (current.role == 'ADMIN') return false;
    final next = List<AppUser>.from(users.value);
    next[idx] = current.copyWith(
      amountLimit: amountLimit,
      digit1CountLimit: digit1CountLimit,
      digit2CountLimit: digit2CountLimit,
      digit3CountLimit: digit3CountLimit,
    );
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool deleteUser(String username) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;

    final target = users.value[idx];

    final isSelf = target.username.trim().toLowerCase() ==
        AppSession.username.trim().toLowerCase();
    if (isSelf) return false;

    if (target.role == "ADMIN") {
      final admins = users.value.where((x) => x.role == "ADMIN").length;
      if (admins <= 1) return false;
    }

    final next = List<AppUser>.from(users.value)..removeAt(idx);
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }
}

class BillRecord {
  final int billNo;
  final DateTime createdAt;
  final DateTime businessDate;
  final String drawName;
  final List<Map<String, dynamic>> rows;
  final String username;
  final String customerName;

  const BillRecord({
    required this.billNo,
    required this.createdAt,
    required this.businessDate,
    required this.rows,
    required this.username,
    this.drawName = '',
    this.customerName = '',
  });

  String get billNote => customerName.trim();

  DateTime get reportCalendarDate => _calendarDate(businessDate);

  static void _normalizeRowMap(Map<String, dynamic> row) {
    row["amount"] = readRowAmount(row["amount"]);
    if (row.containsKey('rate')) {
      row['rate'] = readRowRate(row['rate']);
    }
  }

  static double readRowRate(dynamic v) => readBookingRate(v);

  static double readRowAmount(dynamic v) {
    if (v is bool) return v ? 1.0 : 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static double readWinningPrize(dynamic v) {
    if (v is bool) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  static double winningWinFromRow(Map<String, dynamic> row) {
    if (row.containsKey('winningWinAmount')) {
      return readWinningPrize(row['winningWinAmount']);
    }
    return readWinningPrize(row['winningPrize']);
  }

  static double winningSuperFromRow(Map<String, dynamic> row) {
    return readWinningPrize(row['winningSuperAmount']);
  }

  static double winningTotalFromRow(Map<String, dynamic> row) {
    if (row.containsKey('winningAmount')) {
      return readWinningPrize(row['winningAmount']);
    }
    if (row.containsKey('winningWinAmount') ||
        row.containsKey('winningSuperAmount')) {
      return winningWinFromRow(row) + winningSuperFromRow(row);
    }
    return readWinningPrize(row['winningPrize']);
  }

  String get effectiveDrawName =>
      drawName.trim().isNotEmpty ? drawName.trim() : drawTimeName;

  Map<String, dynamic> toJson() => {
        "billNo": billNo,
        "createdAt": createdAt.toUtc().toIso8601String(),
        "businessDate": _calendarDate(businessDate).toIso8601String(),
        "drawName": effectiveDrawName,
        "username": username,
        "customerName": customerName,
        "rows": rows.map((r) => Map<String, dynamic>.from(r)).toList(),
      };

  static BillRecord? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final billRaw = json["billNo"];
    final int? billNo = billRaw is int
        ? billRaw
        : billRaw is num
            ? billRaw.toInt()
            : int.tryParse(billRaw?.toString() ?? "");
    final parsedCreated = _parseDateTime(json["createdAt"]);
    final username = json["username"]?.toString() ?? "";
    final customerName = _readBillNoteFromJson(json);
    if (billNo == null || parsedCreated == null) return null;
    final created = parsedCreated.toLocal();
    final drawNameRaw = json["drawName"]?.toString() ?? '';

    final rowsRaw = json["rows"];
    if (rowsRaw is! List) return null;
    final rows = <Map<String, dynamic>>[];
    for (final item in rowsRaw) {
      Map<String, dynamic>? m;
      if (item is Map<String, dynamic>) {
        m = Map<String, dynamic>.from(item);
      } else if (item is Map) {
        m = Map<String, dynamic>.from(item);
      }
      if (m != null) {
        _normalizeRowMap(m);
        rows.add(m);
      }
    }

    final parsedBusiness = _parseDateTime(
      json["businessDate"] ?? json["salesDate"],
    );
    final businessDate = _resolveBookingBusinessDate(
      createdAt: created,
      drawName: drawNameRaw,
      rows: rows,
      parsedBusiness: parsedBusiness,
    );

    final resolvedDrawName = drawNameRaw.trim().isNotEmpty
        ? drawNameRaw.trim()
        : (rows.isNotEmpty
            ? DrawScheduleStore.drawTimeFromRowType(
                rows.first['type'].toString(),
              )
            : '');

    return BillRecord(
        billNo: billNo,
        createdAt: created,
        businessDate: businessDate,
        drawName: resolvedDrawName,
        rows: rows,
        username: username,
        customerName: customerName);
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return DateTime.tryParse(raw);
    if (raw is Map) {
      final nested = raw[r'$date'] ?? raw['date'];
      if (nested != null) return DateTime.tryParse(nested.toString());
    }
    return DateTime.tryParse(raw.toString());
  }

  static String _readBillNoteFromJson(Map<String, dynamic> json) {
    for (final key in const [
      'customerName',
      'customer_name',
      'billNote',
      'bill_note',
    ]) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  int get totalCount => rows.fold<int>(
        0,
        (total, row) => total + (int.tryParse(row["count"].toString()) ?? 0),
      );

  double get totalAmount => rows.fold<double>(
        0.0,
        (total, row) => total + BillRecord.readRowAmount(row["amount"]),
      );

  String get drawTimeName {
    if (rows.isEmpty) return kDrawTimeNames.first;
    return DrawScheduleStore.drawTimeFromRowType(rows.first['type'].toString());
  }

  bool isModifiable({DateTime? at}) => DrawScheduleStore.isBillModifiable(
        billBusinessDate: businessDate,
        drawTime: drawTimeName,
        at: at,
      );

  String? modifyBlockMessage({DateTime? at}) =>
      DrawScheduleStore.billModifyBlockMessage(
        billBusinessDate: businessDate,
        drawTime: drawTimeName,
        at: at,
      );

  /// Fix legacy rows: businessDate + amount from stored decimal rate.
  BillRecord normalizedForReports() {
    final draw = effectiveDrawName;
    var reportDate = businessDate;
    if (draw.isNotEmpty) {
      final expected =
          DrawScheduleStore.businessDateForDraw(draw, at: createdAt);
      if (isSameBusinessDate(reportDate, createdAt) &&
          !isSameBusinessDate(expected, createdAt)) {
        reportDate = expected;
      }
    }

    final scheme = PriceListStore.gameRatesFor(username).billingScheme;
    final fixedRows = rows.map((row) {
      final m = Map<String, dynamic>.from(row);
      _normalizeRowMap(m);
      if (m.containsKey('rate')) {
        final rate = readRowRate(m['rate']);
        final count = int.tryParse(m['count'].toString()) ?? 0;
        if (rate > 0 && count > 0) {
          m['amount'] = applyBillingSchemeAmount(
            bookingAmountFromRate(rate, count),
            scheme,
          );
        }
      }
      return m;
    }).toList();

    return BillRecord(
      billNo: billNo,
      createdAt: createdAt,
      businessDate: reportDate,
      drawName: drawName.trim().isNotEmpty ? drawName : draw,
      rows: fixedRows,
      username: username,
      customerName: customerName,
    );
  }
}

class BillsStore {
  static const String _prefsKey = "app_bills_v1";
  static final ValueNotifier<List<BillRecord>> bills =
      ValueNotifier<List<BillRecord>>([]);
  static Timer? _saveDebounce;

  static Future<void> init() async {
    final List<BillRecord> localBills = [];
    if (!kIsWeb) {
      final maps = await AppDatabase.loadAllBillMaps();
      for (final m in maps) {
        final b = BillRecord.fromJson(m);
        if (b != null) localBills.add(b);
      }
    } else {
      final String? raw = await LegacyPrefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            final b = BillRecord.fromJson(Map<String, dynamic>.from(item));
            if (b != null) localBills.add(b);
          }
        }
      }
    }
    bills.value = localBills.map((b) => b.normalizedForReports()).toList();
    await purgeExpired();
    await saveNow();
  }

  static Future<int> purgeExpired({DateTime? at}) async {
    final cutoff = retentionCutoffDate(at: at);
    final kept = bills.value.where((b) {
      final day = DateTime(
        b.createdAt.year,
        b.createdAt.month,
        b.createdAt.day,
      );
      return !day.isBefore(cutoff);
    }).toList();
    final removed = bills.value.length - kept.length;
    if (removed > 0) {
      bills.value = kept;
      await saveNow();
      debugPrint('BillsStore retention: removed $removed bills');
    }
    return removed;
  }

  static void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce =
        Timer(const Duration(milliseconds: 200), () => unawaited(saveNow()));
  }

  static Future<void> saveNow() async {
    final payload = bills.value.map((b) => b.toJson()).toList();
    if (kIsWeb) {
      await LegacyPrefs.setString(_prefsKey, jsonEncode(payload));
    } else {
      await AppDatabase.replaceBills(payload);
    }
  }

  static void add(BillRecord r) {
    bills.value = [r, ...bills.value];
    unawaited(_persistAndSyncBooking(r));
  }

  static Future<void> _persistAndSyncBooking(BillRecord r) async {
    await saveNow();
    debugPrint('Booking saved local: billNo=${r.billNo}');
    await SyncService.syncBooking(r.toJson());
  }

  static BillRecord? byBillNo(int no) {
    try {
      return bills.value.firstWhere((b) => b.billNo == no);
    } catch (_) {
      return null;
    }
  }

  static Iterable<BillRecord> billsForBusinessDate(
    DateTime businessDate, {
    String? username,
  }) {
    return bills.value.where((b) {
      if (!isSameBusinessDate(b.businessDate, businessDate)) return false;
      if (username == null) return true;
      return b.username.trim().toLowerCase() ==
          username.trim().toLowerCase();
    });
  }

  static Iterable<BillRecord> todayBillsForUser(
    String username, {
    DateTime? businessDate,
  }) {
    final key = username.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final day = businessDate ?? DrawScheduleStore.currentBusinessDate();
    return billsForBusinessDate(day, username: username);
  }

  static double todayAmountForUser(String username, {DateTime? businessDate}) {
    return todayBillsForUser(username, businessDate: businessDate)
        .fold<double>(
      0.0,
      (total, bill) => total + bill.totalAmount,
    );
  }

  static int _digitCountInRows(Iterable<Map<String, dynamic>> rows, String mode) {
    return rows.fold<int>(0, (total, row) {
      final len = row['number'].toString().trim().length;
      final matches = mode == '1'
          ? len == 1
          : mode == '2'
              ? len == 2
              : len >= 3;
      if (!matches) return total;
      return total + (int.tryParse(row['count'].toString()) ?? 0);
    });
  }

  static int todayDigitCountForUser(
    String username,
    String mode, {
    DateTime? businessDate,
  }) {
    return todayBillsForUser(username, businessDate: businessDate).fold<int>(
      0,
      (total, bill) => total + _digitCountInRows(bill.rows, mode),
    );
  }

  static void delete(int no) {
    final bill = byBillNo(no);
    if (bill != null && !bill.isModifiable()) return;
    bills.value = bills.value.where((b) => b.billNo != no).toList();
    unawaited(_persistAndSyncDelete(no));
  }

  static Future<void> _persistAndSyncDelete(int no) async {
    await saveNow();
    await SyncService.queueBookingDelete(no);
  }

  static void notifyUpdated([BillRecord? bill]) {
    if (bill != null && !bill.isModifiable()) return;
    bills.value = [...bills.value];
    if (bill != null) {
      unawaited(_persistAndSyncBooking(bill));
    } else {
      _scheduleSave();
    }
  }
}

class ResultSnapshot {
  final String drawCode;
  final DateTime date;
  final List<String> prizes; // 5
  final List<String> compliments; // 30
  final bool manualOverride;
  final String? autoStatus;
  final Map<String, String>? source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ResultSnapshot({
    required this.drawCode,
    required this.date,
    required this.prizes,
    required this.compliments,
    this.manualOverride = false,
    this.autoStatus,
    this.source,
    this.createdAt,
    this.updatedAt,
  });

  ResultSnapshot copyWith({
    String? drawCode,
    DateTime? date,
    List<String>? prizes,
    List<String>? compliments,
    bool? manualOverride,
    String? autoStatus,
    Map<String, String>? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ResultSnapshot(
      drawCode: drawCode ?? this.drawCode,
      date: date ?? this.date,
      prizes: prizes ?? this.prizes,
      compliments: compliments ?? this.compliments,
      manualOverride: manualOverride ?? this.manualOverride,
      autoStatus: autoStatus ?? this.autoStatus,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        "drawCode": drawCode,
        "date": DateTime(date.year, date.month, date.day).toIso8601String(),
        "prizes": prizes,
        "compliments": compliments,
        "manualOverride": manualOverride,
        if (autoStatus != null) "autoStatus": autoStatus,
        if (source != null && source!.isNotEmpty) "source": source,
        if (createdAt != null) "createdAt": createdAt!.toIso8601String(),
        if (updatedAt != null) "updatedAt": updatedAt!.toIso8601String(),
      };

  static Map<String, String>? _sourceFromJson(dynamic raw) {
    if (raw is! Map) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  static ResultSnapshot? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final parsed = DateTime.tryParse(json["date"]?.toString() ?? "");
    if (parsed == null) return null;
    final pRaw = json["prizes"];
    final cRaw = json["compliments"];
    if (pRaw is! List || cRaw is! List) return null;
    final drawCode = (json["drawCode"]?.toString() ?? "").trim().toUpperCase();
    if (!ResultStore.isValidDrawCode(drawCode)) return null;
    return ResultSnapshot(
      drawCode: drawCode,
      date: parsed,
      prizes: pRaw.map((e) => e.toString()).toList(),
      compliments: cRaw.map((e) => e.toString()).toList(),
      manualOverride: json["manualOverride"] == true,
      autoStatus: json["autoStatus"]?.toString(),
      source: _sourceFromJson(json["source"]),
      createdAt: DateTime.tryParse(json["createdAt"]?.toString() ?? ""),
      updatedAt: DateTime.tryParse(json["updatedAt"]?.toString() ?? ""),
    );
  }
}

List<String> complimentsAscendingOrder(Iterable<String> raw) =>
    KeralaComplimentRules.forDisplay(raw);

bool _keralaComplimentsValid(Iterable<String> raw) =>
    KeralaComplimentRules.complimentsLookValid(raw);

bool _keralaComplimentsSame(List<String> a, List<String> b) =>
    !_keralaComplimentSetsDiffer(a, b);

bool _keralaComplimentSetsDiffer(List<String> a, List<String> b) {
  final sa = a
      .where(KeralaComplimentRules.isValidComplimentCell)
      .map(KeralaComplimentRules.normalizeCompliment3)
      .toSet();
  final sb = b
      .where(KeralaComplimentRules.isValidComplimentCell)
      .map(KeralaComplimentRules.normalizeCompliment3)
      .toSet();
  return sa.length != sb.length || !sa.containsAll(sb);
}

int _keralaValidComplimentCount(Iterable<String> raw) =>
    raw.where(KeralaComplimentRules.isValidComplimentCell).length;

List<String> _mergeKeralaComplimentProgress(
  List<String> stored,
  List<String> incoming,
) {
  final out = complimentsAscendingOrder(stored);
  final inc = complimentsAscendingOrder(incoming);
  final merged = List<String>.filled(KeralaComplimentRules.complimentCount, '---');
  for (var i = 0; i < KeralaComplimentRules.complimentCount; i++) {
    final ex = i < out.length ? out[i] : '---';
    final ic = i < inc.length ? inc[i] : '---';
    merged[i] = KeralaComplimentRules.isValidComplimentCell(ex)
        ? ex
        : (KeralaComplimentRules.isValidComplimentCell(ic) ? ic : '---');
  }
  return complimentsAscendingOrder(merged);
}

String _fiveDigitFirstPrize(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9]'), '');

bool _isValidResultCell(String v) {
  final t = v.trim();
  return t.isNotEmpty && t != '---';
}

bool _keralaResultAlreadySaved(ResultSnapshot snapshot) {
  if (snapshot.prizes.length < 5) return false;
  for (var i = 0; i < 5; i++) {
    if (!_isValidResultCell(snapshot.prizes[i])) return false;
  }
  final firstDigits = _fiveDigitFirstPrize(snapshot.prizes[0]);
  if (firstDigits.length < 3) return false;
  return _keralaComplimentsValid(snapshot.compliments);
}

ResultSnapshot _sanitizeResultSnapshot(ResultSnapshot snapshot) {
  if (snapshot.drawCode.trim().toUpperCase() != 'LSK3') {
    return snapshot;
  }
  final prizes = List<String>.from(snapshot.prizes);
  while (prizes.length < 5) {
    prizes.add('---');
  }
  if (_isValidResultCell(prizes[0])) {
    prizes[0] = KeralaComplimentRules.normalizeCompliment3(prizes[0]);
  }
  final compliments = complimentsAscendingOrder(snapshot.compliments);
  return snapshot.copyWith(
    prizes: prizes.take(5).toList(),
    compliments: compliments,
  );
}

ResultSnapshot _mergeKeralaFetched(
  ResultSnapshot? existing,
  FetchedResultData incoming, {
  bool forceOverwrite = false,
}) {
  final manual = existing?.manualOverride == true && !forceOverwrite;
  final prizes = List<String>.filled(5, '---');
  for (var i = 0; i < 5; i++) {
    final inc = i < incoming.prizes.length ? incoming.prizes[i] : '---';
    final ex =
        existing != null && i < existing.prizes.length ? existing.prizes[i] : '---';
    if (manual && i > 0 && _isValidResultCell(ex)) {
      prizes[i] = ex;
    } else {
      prizes[i] = _isValidResultCell(inc)
          ? inc
          : (_isValidResultCell(ex) ? ex : '---');
    }
  }

  final storedNorm = complimentsAscendingOrder(existing?.compliments ?? const []);
  final incomingNorm = complimentsAscendingOrder(incoming.compliments);
  final storedValid = _keralaComplimentsValid(storedNorm);
  final incomingValid = _keralaComplimentsValid(incomingNorm);

  var compliments = storedNorm;
  if (manual && storedValid) {
    compliments = storedNorm;
  } else if (forceOverwrite && incomingValid) {
    compliments = incomingNorm;
  } else if (incomingValid &&
      (!storedValid || _keralaComplimentSetsDiffer(storedNorm, incomingNorm))) {
    compliments = incomingNorm;
  } else if (_keralaValidComplimentCount(incomingNorm) >
      _keralaValidComplimentCount(storedNorm)) {
    compliments = _mergeKeralaComplimentProgress(storedNorm, incomingNorm);
  }

  return _sanitizeResultSnapshot(
    ResultSnapshot(
      drawCode: 'LSK3',
      date: incoming.date,
      prizes: prizes,
      compliments: compliments,
      manualOverride: existing?.manualOverride ?? false,
    ),
  );
}

Future<bool> _refreshKeralaFromNet(
  DateTime day, {
  bool forceOverwrite = false,
  bool userTriggered = false,
}) async {
  if (ResultStore.isUserDeleted('LSK3', day)) return false;
  var changed = false;

  Future<void> mergeAndSave(FetchedResultData fetched) async {
    final existing = ResultStore.get('LSK3', day);
    final merged = _mergeKeralaFetched(
      existing,
      fetched,
      forceOverwrite: forceOverwrite,
    );
    if (ResultStore.signature(merged) != ResultStore.signature(existing)) {
      ResultStore.save(merged);
      changed = true;
    }
  }

  final apiFetched = await ResultFetchService.fetchDraw('LSK3', day);
  if (apiFetched != null) {
    await mergeAndSave(apiFetched);
  }

  await KeralaAutoResultService.instance.tick(
    day,
    userTriggered: userTriggered || forceOverwrite,
    onSave: mergeAndSave,
  );

  return changed;
}

Future<bool> _refreshDearFromNet(String drawCode, DateTime day) async {
  final code = drawCode.trim().toUpperCase();
  if (!DearAutoResultService.isDearDraw(code)) return false;
  if (ResultStore.isUserDeleted(code, day)) return false;

  final existing = ResultStore.get(code, day);
  final merged = await DearAutoResultService.instance.fetchAndMerge(
    drawCode: code,
    day: day,
    existingPrizes: existing?.prizes ?? const [],
    existingCompliments: existing?.compliments ?? const [],
    manualFirstPrize: existing?.manualOverride == true,
  );
  if (merged == null) return false;

  final now = DateTime.now();
  final snapshot = ResultSnapshot(
    drawCode: code,
    date: day,
    prizes: merged.prizes,
    compliments: merged.compliments,
    manualOverride: existing?.manualOverride ?? false,
    autoStatus: merged.autoStatus,
    source: merged.source.isEmpty ? existing?.source : merged.source,
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
  );

  final before = ResultStore.signature(existing);
  final after = ResultStore.signature(snapshot);
  if (after == before) {
    debugPrint('DEAR_AUTO_SKIP_DUPLICATE draw=$code date=$day');
    return false;
  }

  debugPrint('DEAR_AUTO_UPDATE_SECTIONS draw=$code date=$day status=${merged.autoStatus}');
  ResultStore.save(snapshot);
  return true;
}

ResultSnapshot _applyDearHybridMerge(
  ResultSnapshot? existing,
  ResultSnapshot incoming, {
  bool fetchedFromWeb = true,
}) {
  final manualFirst = existing?.manualOverride == true;
  final merged = DearAutoResultService.mergeHybrid(
    existingPrizes: existing?.prizes ?? incoming.prizes,
    existingCompliments: existing?.compliments ?? incoming.compliments,
    manualFirstPrize: manualFirst,
    incomingPrizes: incoming.prizes,
    incomingCompliments: incoming.compliments,
    fetchedFromWeb: fetchedFromWeb,
  );
  final now = DateTime.now();
  return incoming.copyWith(
    prizes: merged.prizes,
    compliments: merged.compliments,
    manualOverride: manualFirst,
    autoStatus: merged.autoStatus,
    source: merged.source.isEmpty ? existing?.source : merged.source,
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
  );
}

class ResultStore {
  static const String _prefsKey = "app_results_v1";
  static const String _deletedPrefsKey = "app_results_deleted_v1";

  static const Set<String> _validDrawCodes = {
    'DEAR1',
    'LSK3',
    'DEAR6',
    'DEAR8',
  };

  static String resultKey(String drawCode, DateTime date) =>
      _key(drawCode, date);

  static bool isValidDrawCode(String drawCode) =>
      _validDrawCodes.contains(drawCode.trim().toUpperCase());

  static final ValueNotifier<Map<String, ResultSnapshot>> results =
      ValueNotifier<Map<String, ResultSnapshot>>({});

  static Timer? _saveDebounce;
  static Set<String> _userDeletedKeys = {};

  static String _key(String drawCode, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return "$drawCode-${d.year}-${d.month}-${d.day}";
  }

  static bool isUserDeleted(String drawCode, DateTime date) =>
      _userDeletedKeys.contains(_key(drawCode, date));

  static void _markUserDeleted(String drawCode, DateTime date) {
    _userDeletedKeys.add(_key(drawCode, date));
  }

  static void _clearUserDeleted(String drawCode, DateTime date) {
    _userDeletedKeys.remove(_key(drawCode, date));
  }

  static Future<void> _loadDeletedKeys() async {
    final String? raw = kIsWeb
        ? await LegacyPrefs.getString(_deletedPrefsKey)
        : await LocalDatabase.getString(_deletedPrefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _userDeletedKeys = decoded.map((e) => e.toString()).toSet();
      }
    } catch (e) {
      debugPrint('ResultStore deleted keys load error: $e');
    }
  }

  static Future<void> _saveDeletedKeys() async {
    final json = jsonEncode(_userDeletedKeys.toList());
    if (kIsWeb) {
      await LegacyPrefs.setString(_deletedPrefsKey, json);
    } else {
      await LocalDatabase.setString(_deletedPrefsKey, json);
    }
  }

  static void _purgeExpiredDeletedKeys(DateTime cutoff) {
    final next = <String>{};
    for (final key in _userDeletedKeys) {
      final parts = key.split('-');
      if (parts.length < 4) {
        next.add(key);
        continue;
      }
      final y = int.tryParse(parts[parts.length - 3]);
      final m = int.tryParse(parts[parts.length - 2]);
      final d = int.tryParse(parts[parts.length - 1]);
      if (y == null || m == null || d == null) {
        next.add(key);
        continue;
      }
      final day = DateTime(y, m, d);
      if (!day.isBefore(cutoff)) next.add(key);
    }
    _userDeletedKeys = next;
  }

  static Future<void> init() async {
    final String? raw = kIsWeb
        ? await LegacyPrefs.getString(_prefsKey)
        : await AppDatabase.loadResultsJson();

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final map = <String, ResultSnapshot>{};
          for (final item in decoded) {
            final s = ResultSnapshot.fromJson(Map<String, dynamic>.from(item));
            if (s != null) map[_key(s.drawCode, s.date)] = s;
          }
          results.value = map;
        }
      } catch (e) {
        debugPrint("Local results load error: $e");
      }
    }
    await _loadDeletedKeys();
    await purgeExpired();
  }

  static Future<int> purgeExpired({DateTime? at}) async {
    final cutoff = retentionCutoffDate(at: at);
    final next = <String, ResultSnapshot>{};
    var removed = 0;
    for (final entry in results.value.entries) {
      final day = DateTime(
        entry.value.date.year,
        entry.value.date.month,
        entry.value.date.day,
      );
      if (day.isBefore(cutoff)) {
        removed++;
        continue;
      }
      next[entry.key] = entry.value;
    }
    _purgeExpiredDeletedKeys(cutoff);
    if (removed > 0) {
      results.value = next;
      await saveNow();
      debugPrint('ResultStore retention: removed $removed results');
    }
    await _saveDeletedKeys();
    return removed;
  }

  static void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(saveNow());
    });
  }

  static Future<void> saveNow() async {
    final list = results.value.values.map((s) => s.toJson()).toList();
    if (kIsWeb) {
      await LegacyPrefs.setString(_prefsKey, jsonEncode(list));
    } else {
      await AppDatabase.replaceResults(list);
    }
  }

  static ResultSnapshot? get(String drawCode, DateTime date) =>
      results.value[_key(drawCode, date)];

  static void save(ResultSnapshot snapshot) {
    final code = snapshot.drawCode.trim().toUpperCase();
    if (!isValidDrawCode(code)) {
      debugPrint('ResultStore.save rejected drawCode: ${snapshot.drawCode}');
      return;
    }
    if (isUserDeleted(code, snapshot.date) && !snapshot.manualOverride) {
      return;
    }
    final key = _key(code, snapshot.date);
    final existing = results.value[key];
    var incoming = snapshot;
    if (existing?.manualOverride == true && !snapshot.manualOverride) {
      if (DearAutoResultService.isDearDraw(code)) {
        incoming = _applyDearHybridMerge(existing, snapshot);
      } else {
        incoming = mergeProtectingManualExceptFirst(existing!, snapshot);
      }
    }
    if (!shouldAcceptIncoming(existing: existing, incoming: incoming)) {
      return;
    }
    var normalized = (incoming.prizes.isEmpty
        ? incoming
        : incoming.copyWith(
            prizes: [
              _firstPrizeLast3(incoming.prizes.first),
              ...incoming.prizes.skip(1),
            ],
          )).copyWith(drawCode: code);
    normalized = _sanitizeResultSnapshot(normalized);
    final now = DateTime.now();
    normalized = normalized.copyWith(
      createdAt: existing?.createdAt ?? normalized.createdAt ?? now,
      updatedAt: now,
    );
    final map = {...results.value};
    map[key] = normalized;
    results.value = map;
    _scheduleSave();
    unawaited(SyncService.queueResult(normalized.toJson()));
  }

  static void saveManual(ResultSnapshot snapshot) {
    final code = snapshot.drawCode.trim().toUpperCase();
    _clearUserDeleted(code, snapshot.date);
    unawaited(_saveDeletedKeys());
    final now = DateTime.now();
    var s = snapshot.copyWith(manualOverride: true, updatedAt: now);
    if (DearAutoResultService.isDearDraw(code)) {
      s = s.copyWith(
        autoStatus: 'waiting_for_auto_sections',
        source: {
          ...?snapshot.source,
          'firstPrize': 'manual',
        },
        createdAt: snapshot.createdAt ?? now,
      );
    }
    save(s);
  }

  static bool isManualOverride(String drawCode, DateTime date) {
    return get(drawCode, date)?.manualOverride == true;
  }

  static void remove(String drawCode, DateTime date) {
    final code = drawCode.trim().toUpperCase();
    final key = _key(code, date);
    if (!results.value.containsKey(key) && !isUserDeleted(code, date)) return;
    _markUserDeleted(code, date);
    if (results.value.containsKey(key)) {
      final map = {...results.value};
      map.remove(key);
      results.value = map;
    }
    unawaited(saveNow());
    unawaited(_saveDeletedKeys());
    unawaited(SyncService.queueResultDelete(code, date));
  }

  /// Auto-fetch / cloud pull must not replace manual 2nd–5th prizes or compliments (Kerala).
  /// Dear hybrid: manual 1st prize only — see [DearAutoResultService.mergeHybrid].
  static ResultSnapshot mergeProtectingManualExceptFirst(
    ResultSnapshot existing,
    ResultSnapshot incoming,
  ) {
    if (DearAutoResultService.isDearDraw(existing.drawCode)) {
      return _applyDearHybridMerge(existing, incoming, fetchedFromWeb: true);
    }

    final prizes = List<String>.filled(5, '---');
    for (var i = 0; i < 5; i++) {
      final inc = i < incoming.prizes.length ? incoming.prizes[i] : '---';
      final ex = i < existing.prizes.length ? existing.prizes[i] : '---';
      if (i == 0) {
        prizes[i] = _isValidCell(inc) ? inc : (_isValidCell(ex) ? ex : '---');
      } else {
        prizes[i] = _isValidCell(ex) ? ex : (_isValidCell(inc) ? inc : '---');
      }
    }

    final compliments = List<String>.filled(30, '---');
    for (var i = 0; i < 30; i++) {
      final ex =
          i < existing.compliments.length ? existing.compliments[i] : '---';
      final inc =
          i < incoming.compliments.length ? incoming.compliments[i] : '---';
      compliments[i] = _isValidCell(ex) ? ex : (_isValidCell(inc) ? inc : '---');
    }

    return existing.copyWith(
      prizes: prizes,
      compliments: compliments,
      manualOverride: true,
    );
  }

  /// Auto-fetch / cloud pull must not replace Kerala manual 2nd–5th prizes or compliments.
  static bool shouldAcceptIncoming({
    ResultSnapshot? existing,
    required ResultSnapshot incoming,
  }) {
    if (existing?.manualOverride == true && !incoming.manualOverride) {
      if (DearAutoResultService.isDearDraw(existing!.drawCode)) {
        return true;
      }
      if (existing.drawCode.trim().toUpperCase() == 'LSK3' &&
          !_keralaComplimentsValid(existing.compliments)) {
        return true;
      }
      return false;
    }
    return true;
  }

  static String _resultMapKey(String drawCode, DateTime date) =>
      _key(drawCode, date);

  static bool _isValidCell(String v) {
    final t = v.trim();
    return t.isNotEmpty && t != '---';
  }

  /// P1–P5 + 30 compliments + correct 1st prize digit length.
  static bool isComplete(ResultSnapshot? snapshot) {
    if (snapshot == null) return false;
    if (snapshot.drawCode.trim().toUpperCase() == 'LSK3') {
      return _keralaResultAlreadySaved(snapshot);
    }
    if (snapshot.prizes.length < 5) return false;
    if (snapshot.compliments.length < 30) return false;
    for (final p in snapshot.prizes.take(5)) {
      if (!_isValidCell(p)) return false;
    }
    for (final c in snapshot.compliments.take(30)) {
      if (!_isValidCell(c)) return false;
    }
    final firstDigits =
        snapshot.prizes[0].replaceAll(RegExp(r'[^0-9]'), '');
    return firstDigits.length >= 3;
  }

  static String signature(ResultSnapshot? snapshot) {
    if (snapshot == null) return '';
    return '${snapshot.drawCode}|'
        '${snapshot.date.year}-${snapshot.date.month}-${snapshot.date.day}|'
        '${snapshot.prizes.join('\x1f')}|'
        '${snapshot.compliments.join('\x1f')}';
  }

  /// Pull one draw+date from cloud API into local store (not website scrape).
  static Future<ResultSnapshot?> loadOne(
    String drawCode,
    DateTime date,
  ) async {
    if (ApiService.token == null) return null;
    final day = DateTime(date.year, date.month, date.day);
    if (isUserDeleted(drawCode, day)) return null;
    try {
      final items = await ApiService.getResults();
      for (final item in items) {
        final s = ResultSnapshot.fromJson(item);
        if (s == null) continue;
        final sd = DateTime(s.date.year, s.date.month, s.date.day);
        if (s.drawCode == drawCode && sd == day) {
          final existing = get(drawCode, day);
          if (existing?.manualOverride == true) {
            save(mergeProtectingManualExceptFirst(existing!, s));
          } else {
            save(s);
          }
          return get(drawCode, day);
        }
      }
    } catch (e) {
      debugPrint('ResultStore.loadOne error: $e');
    }
    return null;
  }

  static ResultSnapshot _mergeFetched(
    ResultSnapshot? existing,
    FetchedResultData fetched,
  ) {
    if (DearAutoResultService.isDearDraw(fetched.drawCode)) {
      return _applyDearHybridMerge(
        existing,
        ResultSnapshot(
          drawCode: fetched.drawCode,
          date: fetched.date,
          prizes: fetched.prizes,
          compliments: fetched.compliments,
        ),
      );
    }

    final manual = existing?.manualOverride == true;
    final prizes = List<String>.filled(5, '---');
    final compliments = List<String>.filled(30, '---');
    for (var i = 0; i < 5; i++) {
      final inc = i < fetched.prizes.length ? fetched.prizes[i] : '---';
      final ex = existing != null && i < existing.prizes.length
          ? existing.prizes[i]
          : '---';
      if (manual && i > 0 && _isValidCell(ex)) {
        prizes[i] = ex;
      } else {
        prizes[i] = _isValidCell(inc) ? inc : (_isValidCell(ex) ? ex : '---');
      }
    }
    for (var i = 0; i < 30; i++) {
      final inc =
          i < fetched.compliments.length ? fetched.compliments[i] : '---';
      final ex = existing != null && i < existing.compliments.length
          ? existing.compliments[i]
          : '---';
      if (manual && _isValidCell(ex)) {
        compliments[i] = ex;
      } else {
        compliments[i] = _isValidCell(inc) ? inc : (_isValidCell(ex) ? ex : '---');
      }
    }
    return ResultSnapshot(
      drawCode: fetched.drawCode,
      date: fetched.date,
      prizes: prizes,
      compliments: compliments,
      manualOverride: existing?.manualOverride ?? false,
    );
  }

  /// Fetch today's results for all 4 draws from public lottery API.
  static Future<int> refreshTodayFromWeb({DateTime? at}) async {
    final istNow = DearAutoResultService.nowInIndia(at: at);
    final day = DateTime(istNow.year, istNow.month, istNow.day);
    var updated = 0;
    for (final code in ResultFetchService.kTodayDrawCodes) {
      try {
        if (code == 'LSK3') {
          if (await _refreshKeralaFromNet(day)) updated++;
        } else if (DearAutoResultService.isDearDraw(code)) {
          if (await _refreshDearFromNet(code, day)) updated++;
        } else {
          final fetched = await ResultFetchService.fetchDraw(code, day);
          if (fetched == null) continue;
          final existing = get(code, day);
          final before = signature(existing);
          final merged = _mergeFetched(existing, fetched);
          final after = signature(merged);
          if (after != before) {
            save(merged);
            updated++;
          }
        }
      } catch (e) {
        debugPrint('ResultStore.refreshTodayFromWeb $code: $e');
      }
    }
    return updated;
  }

  /// Cloud + web for a single draw/date.
  static Future<bool> refreshDraw(
    String drawCode,
    DateTime date, {
    bool fromWeb = true,
    bool fromCloud = true,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    if (isUserDeleted(drawCode, day)) return false;
    var changed = false;
    if (fromCloud && ApiService.token != null) {
      final before = signature(get(drawCode, day));
      await loadOne(drawCode, day);
      if (signature(get(drawCode, day)) != before) changed = true;
    }
    if (fromWeb) {
      try {
        final existing = get(drawCode, day);

        final now = DateTime.now();
        final istNow = DearAutoResultService.nowInIndia(at: now);
        final isToday = ResultFetchService.isSameCalendarDay(day, istNow);
        final code = drawCode.trim().toUpperCase();
        final beforeLiveStart = DearAutoResultService.isDearDraw(code)
            ? !DearAutoResultService.isAtOrAfterAutoCheck(code, at: istNow)
            : !ResultFetchService.isAtOrAfterLiveStart(drawCode, now);
        if (isToday && beforeLiveStart) {
          if (existing != null && !existing.manualOverride) {
            remove(drawCode, day);
            changed = true;
          }
          return changed;
        }

        if (code == 'LSK3') {
          final keralaChanged = await _refreshKeralaFromNet(
            day,
            userTriggered: false,
          );
          if (keralaChanged) changed = true;
        } else if (DearAutoResultService.isDearDraw(code)) {
          final dearChanged = await _refreshDearFromNet(code, day);
          if (dearChanged) changed = true;
        } else {
          final fetched = await ResultFetchService.fetchDraw(drawCode, day);
          if (fetched != null) {
            final existing = get(drawCode, day);
            final before = signature(existing);
            final merged = _mergeFetched(existing, fetched);
            if (signature(merged) != before) {
              save(merged);
              changed = true;
            }
          } else if (isToday &&
              ResultFetchService.isAtOrAfterLiveStart(drawCode, now) &&
              DearAutoResultService.isDearDraw(code) &&
              isComplete(existing)) {
            final published =
                await ResultFetchService.todayDearPublishedOnWeb(drawCode, day);
            if (!published) {
              remove(drawCode, day);
              changed = true;
            }
          }
        }
      } catch (e) {
        debugPrint('ResultStore.refreshDraw web $drawCode: $e');
      }
    }
    return changed;
  }

  /// Background Dear hybrid auto-fetch for today's draws (IST schedule).
  static Future<int> refreshDearDrawsIfNeeded({DateTime? at}) async {
    final ist = DearAutoResultService.nowInIndia(at: at);
    final day = DateTime(ist.year, ist.month, ist.day);
    var updated = 0;
    for (final code in DearAutoResultService.dearDrawCodes) {
      if (!DearAutoResultService.isAtOrAfterAutoCheck(code, at: ist)) continue;
      if (isUserDeleted(code, day)) continue;
      final snap = get(code, day);
      if (snap != null) {
        if (!snap.manualOverride && isComplete(snap)) continue;
        if (snap.manualOverride &&
            DearAutoResultService.autoSectionsComplete(
              snap.prizes,
              snap.compliments,
            )) {
          continue;
        }
      }
      if (await _refreshDearFromNet(code, day)) updated++;
    }
    return updated;
  }

  static Future<bool> refreshDearDraw(String drawCode, DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return _refreshDearFromNet(drawCode.trim().toUpperCase(), day);
  }

  /// Background Kerala auto-fetch for today (prizes + compliments).
  static Future<int> refreshKeralaIfNeeded({DateTime? at}) async {
    final ist = DearAutoResultService.nowInIndia(at: at);
    final day = DateTime(ist.year, ist.month, ist.day);
    if (isUserDeleted('LSK3', day)) return 0;
    if (!ResultFetchService.isAtOrAfterLiveStart('LSK3', ist)) return 0;
    final snap = get('LSK3', day);
    if (snap != null && _keralaResultAlreadySaved(snap)) return 0;
    debugPrint('KERALA_AUTO_START date=$day');
    final changed = await _refreshKeralaFromNet(day);
    if (changed) {
      debugPrint('KERALA_AUTO_UPDATE date=$day');
    }
    return changed ? 1 : 0;
  }

  static Future<int> loadAllForDate(DateTime date, {bool fromWeb = true}) async {
    final day = DateTime(date.year, date.month, date.day);
    var updated = 0;
    if (ApiService.token != null) {
      try {
        final items = await ApiService.getResults();
        for (final item in items) {
          final s = ResultSnapshot.fromJson(item);
          if (s == null) continue;
          final sd = DateTime(s.date.year, s.date.month, s.date.day);
          if (sd != day) continue;
          if (isUserDeleted(s.drawCode, day)) continue;
          if (!ResultFetchService.kTodayDrawCodes.contains(s.drawCode)) {
            continue;
          }
          if (!shouldAcceptIncoming(
            existing: get(s.drawCode, day),
            incoming: s,
          )) {
            continue;
          }
          final existing = get(s.drawCode, day);
          final before = signature(existing);
          if (existing?.manualOverride == true &&
              DearAutoResultService.isDearDraw(s.drawCode)) {
            save(_applyDearHybridMerge(existing, s));
          } else {
            save(s);
          }
          if (signature(get(s.drawCode, day)) != before) updated++;
        }
      } catch (e) {
        debugPrint('ResultStore.loadAllForDate cloud: $e');
      }
    }
    if (fromWeb) {
      final istToday = DearAutoResultService.nowInIndia();
      final istDay = DateTime(istToday.year, istToday.month, istToday.day);
      final isToday = day.year == istDay.year &&
          day.month == istDay.month &&
          day.day == istDay.day;
      if (isToday) {
        updated += await refreshTodayFromWeb(at: day);
      } else {
        for (final code in ResultFetchService.kTodayDrawCodes) {
          if (await refreshDraw(code, day, fromWeb: true, fromCloud: false)) {
            updated++;
          }
        }
      }
    }
    return updated;
  }
}

/// Replace local bookings with cloud data (source of truth), preserving businessDate when cloud omits it.
String _mergeBillNote(BillRecord cloud, BillRecord local) {
  if (cloud.billNote.isNotEmpty) return cloud.billNote;
  return local.billNote;
}

Future<void> _replaceCloudBookings(List<dynamic> bookingsRaw) async {
  debugPrint('Replace bookings from cloud count: ${bookingsRaw.length}');

  final existingByNo = {
    for (final b in BillsStore.bills.value) b.billNo: b,
  };

  final loaded = <BillRecord>[];
  var parsed = 0;
  for (final item in bookingsRaw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final hasBusinessDateInPayload =
        map['businessDate'] != null || map['salesDate'] != null;
    final hasDrawNameInPayload =
        (map['drawName']?.toString().trim().isNotEmpty ?? false);

    var b = BillRecord.fromJson(map);
    if (b == null) {
      debugPrint('Booking parse failed: $map');
      continue;
    }

    final local = existingByNo[b.billNo];
    if (local != null) {
      if (!hasBusinessDateInPayload) {
        b = BillRecord(
          billNo: b.billNo,
          createdAt: b.createdAt,
          businessDate: local.businessDate,
          drawName: local.drawName,
          rows: b.rows,
          username: b.username,
          customerName: _mergeBillNote(b, local),
        );
      } else if (!hasDrawNameInPayload && local.drawName.trim().isNotEmpty) {
        b = BillRecord(
          billNo: b.billNo,
          createdAt: b.createdAt,
          businessDate: b.businessDate,
          drawName: local.drawName,
          rows: b.rows,
          username: b.username,
          customerName: _mergeBillNote(b, local),
        );
      } else if (b.billNote.isEmpty && local.billNote.isNotEmpty) {
        b = BillRecord(
          billNo: b.billNo,
          createdAt: b.createdAt,
          businessDate: b.businessDate,
          drawName: b.drawName,
          rows: b.rows,
          username: b.username,
          customerName: local.billNote,
        );
      }
    }

    loaded.add(b.normalizedForReports());
    parsed++;
  }

  loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  BillsStore.bills.value = loaded;
  await BillsStore.saveNow();
  debugPrint(
    'SQLite bookings replaced: ${loaded.length} (parsed: $parsed)',
  );
}

/// Pull latest bookings from cloud with retries.
Future<void> pullBookingsFromCloud() async {
  if (ApiService.token == null) {
    debugPrint('Pull bookings skipped: no auth token');
    return;
  }

  for (var attempt = 1; attempt <= 2; attempt++) {
    try {
      final items = await ApiService.getBookings();
      debugPrint('Pull bookings attempt $attempt count: ${items.length}');
      await _replaceCloudBookings(items);
      return;
    } catch (e) {
      debugPrint('Pull bookings attempt $attempt failed: $e');
      if (attempt < 2) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }
}

bool _postLoginSyncScheduled = false;

void schedulePostLoginSync() {
  if (_postLoginSyncScheduled) return;
  _postLoginSyncScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(runCloudRestoreAfterLogin());
  });
}

/// Merge cloud restore payload into local stores (after login).
Future<void> applyCloudRestore(Map<String, dynamic> data) async {
  final bookings = data['bookings'];
  if (bookings is List) {
    await _replaceCloudBookings(bookings);
  } else {
    debugPrint('Restore bookings: missing or invalid');
    await pullBookingsFromCloud();
  }

  final settingsRaw = data['settings'];
  if (settingsRaw is Map) {
    final rateSets = settingsRaw['rateSets'];
    if (rateSets is List) RateSetStore.replaceAll(rateSets);
    final priceList = settingsRaw['priceList'];
    if (priceList is Map) {
      PriceListStore.replaceAllFromCloud(
          Map<String, dynamic>.from(priceList));
    }
    final gameRates = settingsRaw['priceListGameRates'];
    if (gameRates is Map) {
      PriceListStore.replaceGameRatesFromCloud(
          Map<String, dynamic>.from(gameRates));
    }
    final drawSchedules = settingsRaw['drawSchedules'];
    if (drawSchedules is Map) {
      DrawScheduleStore.replaceFromCloud(
        Map<String, dynamic>.from(drawSchedules),
      );
    }
    final digitLimits = settingsRaw['digitCountLimits'];
    if (digitLimits is Map) {
      DigitLimitStore.replaceFromCloud(
        Map<String, dynamic>.from(digitLimits),
      );
    }
  }

  final salesRaw = data['sales'];
  if (salesRaw is List && salesRaw.isNotEmpty) {
    final loaded = <SaleEntry>[];
    for (final item in salesRaw) {
      final e = SaleEntry.fromJson(Map<String, dynamic>.from(item as Map));
      if (e != null) loaded.add(e);
    }
    if (loaded.isNotEmpty) {
      SalesStore.sales.value = loaded;
      await SalesStore.saveNow();
    }
  }

  final resultsRaw = data['results'];
  final map = <String, ResultSnapshot>{...ResultStore.results.value};
  if (resultsRaw is List) {
    for (final item in resultsRaw) {
      final s = ResultSnapshot.fromJson(Map<String, dynamic>.from(item as Map));
      if (s != null) {
        final d = DateTime(s.date.year, s.date.month, s.date.day);
        final k = ResultStore._resultMapKey(s.drawCode, d);
        final existing = map[k];
        if (existing?.manualOverride == true && s.manualOverride != true) {
          if (DearAutoResultService.isDearDraw(s.drawCode)) {
            map[k] = _applyDearHybridMerge(existing!, s);
          } else {
            map[k] = ResultStore.mergeProtectingManualExceptFirst(existing!, s);
          }
        } else if (ResultStore.shouldAcceptIncoming(
          existing: existing,
          incoming: s,
        )) {
          map[k] = s;
        }
      }
    }
  }

  // Permanent chart archive → fill gaps so result pages are never blank
  final archive = data['chartArchive'];
  if (archive is List) {
    for (final item in archive) {
      final m = Map<String, dynamic>.from(item as Map);
      final drawCode = m['drawCode']?.toString() ?? '';
      final dateRaw = m['date'];
      if (drawCode.isEmpty || dateRaw == null) continue;
      final parsed = DateTime.tryParse(dateRaw.toString());
      if (parsed == null) continue;
      final d = DateTime(parsed.year, parsed.month, parsed.day);
      final k = '$drawCode-${d.year}-${d.month}-${d.day}';
      map.putIfAbsent(
        k,
        () => ResultSnapshot(
          drawCode: drawCode,
          date: d,
          prizes: (m['prizes'] as List?)?.map((e) => e.toString()).toList() ?? [],
          compliments:
              (m['compliments'] as List?)?.map((e) => e.toString()).toList() ?? [],
        ),
      );
    }
  }

  if (map.isNotEmpty) {
    ResultStore.results.value = map;
    await ResultStore.saveNow();
  }

  await UserStore.pullUsersFromCloud();
}

/// Background cloud restore after login (same logic as before, no UI).
Future<void> runCloudRestoreAfterLogin() async {
  try {
    Map<String, dynamic>? data;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        data = await SyncService.restoreFromCloud(showProgress: false);
        break;
      } catch (e) {
        debugPrint('Cloud restore attempt $attempt failed: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
    if (data != null) {
      await applyCloudRestore(data);
    } else {
      await pullBookingsFromCloud();
    }
    unawaited(SyncService.flushQueue());
  } catch (e) {
    debugPrint('Cloud restore skipped: $e');
    unawaited(pullBookingsFromCloud());
  }
}

String _drawCodeFromType(String type) {
  final t = type.toUpperCase();
  if (t.startsWith("DEAR1")) return "DEAR1";
  if (t.startsWith("DEAR6")) return "DEAR6";
  if (t.startsWith("DEAR8")) return "DEAR8";
  if (t.startsWith("LSK3")) return "LSK3";
  return "";
}

String _drawCodeFromFilter(String drawFilter) {
  final v = drawFilter.toUpperCase().trim();
  if (v == "DEAR 1 PM") return "DEAR1";
  if (v == "DEAR 6 PM") return "DEAR6";
  if (v == "DEAR 8 PM") return "DEAR8";
  if (v == "LSK 3 PM") return "LSK3";
  if (v == "DEAR1" || v == "DEAR6" || v == "DEAR8" || v == "LSK3") return v;
  return "";
}

String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

class _WinningPrizeParts {
  final double base;
  final double superAmount;

  const _WinningPrizeParts({required this.base, required this.superAmount});

  double get total => base + superAmount;

  _WinningPrizeParts multiply(int count) {
    if (count <= 0) return const _WinningPrizeParts(base: 0, superAmount: 0);
    final c = count.toDouble();
    return _WinningPrizeParts(base: base * c, superAmount: superAmount * c);
  }
}

const List<_WinningPrizeParts> _kSuperRowFallbacks = [
  _WinningPrizeParts(base: 5000, superAmount: 400),
  _WinningPrizeParts(base: 500, superAmount: 50),
  _WinningPrizeParts(base: 250, superAmount: 20),
  _WinningPrizeParts(base: 100, superAmount: 20),
  _WinningPrizeParts(base: 50, superAmount: 20),
  _WinningPrizeParts(base: 20, superAmount: 10),
];

const _WinningPrizeParts _kAbcFallback =
    _WinningPrizeParts(base: 100, superAmount: 0);
const _WinningPrizeParts _k2dFallback =
    _WinningPrizeParts(base: 700, superAmount: 30);
const _WinningPrizeParts _kBoxNormalDirectFallback =
    _WinningPrizeParts(base: 3000, superAmount: 300);
const _WinningPrizeParts _kBoxNormalIndirectFallback =
    _WinningPrizeParts(base: 800, superAmount: 30);
const _WinningPrizeParts _kBox2SameDirectFallback =
    _WinningPrizeParts(base: 3800, superAmount: 330);
const _WinningPrizeParts _kBox2SameIndirectFallback =
    _WinningPrizeParts(base: 1600, superAmount: 60);

bool _includeSuperForScheme(String suffix) {
  switch (suffix.toUpperCase()) {
    case 'A':
    case 'B':
    case 'C':
      return false;
    default:
      return true;
  }
}

bool _is2dScheme(String suffix) {
  final s = suffix.toUpperCase();
  return s == 'AB' || s == 'BC' || s == 'AC';
}

bool _isAnagram3(String a, String b) {
  if (a.length != 3 || b.length != 3) return false;
  final ca = a.split('')..sort();
  final cb = b.split('')..sort();
  return ca.join() == cb.join();
}

bool _hasExactlyTwoSameDigits(String s) {
  final d = _digitsOnly(s);
  if (d.length != 3) return false;
  final counts = <String, int>{};
  for (final ch in d.split('')) {
    counts[ch] = (counts[ch] ?? 0) + 1;
  }
  return counts.values.any((n) => n == 2);
}

_WinningPrizeParts _schemeWinningPartsForUser(
  String username,
  String suffix, {
  required int rowIndex,
  required _WinningPrizeParts fallback,
  bool? includeSuper,
}) {
  final useSuper = includeSuper ?? _includeSuperForScheme(suffix);
  final scheme = PriceListStore.dear1SchemeBySuffix(username, suffix);

  var base = fallback.base;
  var superAmt = fallback.superAmount;

  if (scheme != null) {
    final rows = scheme['rows'];
    if (rows is List && rowIndex >= 0 && rowIndex < rows.length) {
      final row = rows[rowIndex];
      if (row is List && row.length >= 3) {
        base = coerceCellInt(row[2]).toDouble();
        superAmt = row.length > 3 ? coerceCellInt(row[3]).toDouble() : 0.0;
      }
    }
  }

  if (useSuper && superAmt <= 0) {
    if (_is2dScheme(suffix) || suffix.toUpperCase() == 'BOX') {
      superAmt = fallback.superAmount;
    }
  }
  if (!useSuper) superAmt = 0;

  return _WinningPrizeParts(base: base, superAmount: superAmt);
}

_WinningPrizeParts _boxWinningPartsForUser(
  String username,
  String ticketNumber,
  String firstPrize, {
  bool includeSuper = true,
}) {
  final ticket = _digitsOnly(ticketNumber);
  final prize = _digitsOnly(firstPrize);
  if (ticket.length != 3 || prize.length != 3) {
    return const _WinningPrizeParts(base: 0, superAmount: 0);
  }
  if (!_isAnagram3(ticket, prize)) {
    return const _WinningPrizeParts(base: 0, superAmount: 0);
  }

  final direct = ticket == prize;
  if (_hasExactlyTwoSameDigits(prize)) {
    return _schemeWinningPartsForUser(
      username,
      'BOX',
      rowIndex: direct ? 6 : 7,
      fallback: direct ? _kBox2SameDirectFallback : _kBox2SameIndirectFallback,
      includeSuper: includeSuper,
    );
  }

  return _schemeWinningPartsForUser(
    username,
    'BOX',
    rowIndex: direct ? 0 : 1,
    fallback: direct ? _kBoxNormalDirectFallback : _kBoxNormalIndirectFallback,
    includeSuper: includeSuper,
  );
}

_WinningPrizeParts? _calculatePrizeParts(
  String suffix,
  String number,
  ResultSnapshot snapshot,
  String username, {
  bool includeSuper = true,
}) {
  final type = suffix.toUpperCase();
  final prizes = snapshot.prizes.map(_digitsOnly).toList();
  final compliments = snapshot.compliments.map(_digitsOnly).toList();

  if (prizes.isEmpty) return null;
  final first = prizes[0];
  if (first.length < 3) return null;

  _WinningPrizeParts? parts;

  if (type == 'A') {
    if (number != first[0]) return null;
    parts = _schemeWinningPartsForUser(
      username,
      'A',
      rowIndex: 0,
      fallback: _kAbcFallback,
      includeSuper: false,
    );
  } else if (type == 'B') {
    if (number.isEmpty || number[0] != first[1]) return null;
    parts = _schemeWinningPartsForUser(
      username,
      'B',
      rowIndex: 0,
      fallback: _kAbcFallback,
      includeSuper: false,
    );
  } else if (type == 'C') {
    if (number.isEmpty || number[0] != first[2]) return null;
    parts = _schemeWinningPartsForUser(
      username,
      'C',
      rowIndex: 0,
      fallback: _kAbcFallback,
      includeSuper: false,
    );
  } else if (type == 'AB') {
    if (number != first.substring(0, 2)) return null;
    parts = _schemeWinningPartsForUser(
      username,
      'AB',
      rowIndex: 0,
      fallback: _k2dFallback,
      includeSuper: includeSuper,
    );
  } else if (type == 'BC') {
    if (number != first.substring(1, 3)) return null;
    parts = _schemeWinningPartsForUser(
      username,
      'BC',
      rowIndex: 0,
      fallback: _k2dFallback,
      includeSuper: includeSuper,
    );
  } else if (type == 'AC') {
    if (number != first[0] + first[2]) return null;
    parts = _schemeWinningPartsForUser(
      username,
      'AC',
      rowIndex: 0,
      fallback: _k2dFallback,
      includeSuper: includeSuper,
    );
  } else if (type == 'BOX') {
    parts = _boxWinningPartsForUser(
      username,
      number,
      first,
      includeSuper: includeSuper,
    );
    if (parts.total <= 0) return null;
  } else if (type == 'SUPER') {
    final rowIndex = _superPrizeRowIndex(number, snapshot);
    if (rowIndex == null) return null;
    final fallback = rowIndex < _kSuperRowFallbacks.length
        ? _kSuperRowFallbacks[rowIndex]
        : const _WinningPrizeParts(base: 0, superAmount: 0);
    parts = _schemeWinningPartsForUser(
      username,
      'SUPER',
      rowIndex: rowIndex,
      fallback: fallback,
      includeSuper: includeSuper,
    );
  }

  if (parts == null || parts.total <= 0) return null;
  return parts;
}

int? _superPrizeRowIndex(String number, ResultSnapshot snapshot) {
  final prizes = snapshot.prizes.map(_digitsOnly).toList();
  final compliments = snapshot.compliments.map(_digitsOnly).toList();
  final n = _digitsOnly(number);
  if (prizes.isNotEmpty && n == prizes[0]) return 0;
  if (prizes.length > 1 && n == prizes[1]) return 1;
  if (prizes.length > 2 && n == prizes[2]) return 2;
  if (prizes.length > 3 && n == prizes[3]) return 3;
  if (prizes.length > 4 && n == prizes[4]) return 4;
  if (compliments.contains(n)) return 5;
  return null;
}

const Set<String> _kOneDigitSchemeSuffixes = {'A', 'B', 'C'};
const Set<String> _kTwoDigitSchemeSuffixes = {'AB', 'BC', 'AC'};

bool _isOneDigitSchemeSuffix(String suffix) =>
    _kOneDigitSchemeSuffixes.contains(suffix.toUpperCase());

bool _isTwoDigitSchemeSuffix(String suffix) =>
    _kTwoDigitSchemeSuffixes.contains(suffix.toUpperCase());

/// Prize / scheme order: 3-digit → 2-digit → 1-digit (SUPER tiers first within 3-digit).
int _schemeSuffixSortKey(String suffix) {
  switch (suffix.toUpperCase()) {
    case 'SUPER':
      return 0;
    case 'BOX':
      return 10;
    case 'AB':
      return 20;
    case 'BC':
      return 21;
    case 'AC':
      return 22;
    case 'A':
      return 30;
    case 'B':
      return 31;
    case 'C':
      return 32;
    default:
      return 99;
  }
}

int _winningDigitTierForType(String type) =>
    schemeGroupFromType(type.trim());

int _winningRowSortKey(Map<String, dynamic> row) {
  final tier = row['winningDigitTier'] as int? ??
      _winningDigitTierForType(row['type']?.toString() ?? '');
  final suffix = schemeSuffixFromName(row['type']?.toString() ?? '');
  final tierBase = (3 - tier) * 100;
  if (suffix.toUpperCase() == 'SUPER') {
    if (row['winningColorKind'] == 'compliments') return tierBase + 5;
    return tierBase + (row['winningPrizeIndex'] as int? ?? 0);
  }
  return tierBase + _schemeSuffixSortKey(suffix);
}

void _sortSchemesThreeTwoOne(List<Map<String, dynamic>> schemes) {
  schemes.sort((a, b) {
    final ka = _schemeSuffixSortKey(
      schemeSuffixFromName(a['name']?.toString() ?? ''),
    );
    final kb = _schemeSuffixSortKey(
      schemeSuffixFromName(b['name']?.toString() ?? ''),
    );
    return ka.compareTo(kb);
  });
}

String _digitGroupDisplayLabel(String group) {
  switch (group) {
    case 'Group 3':
      return '3 Digit';
    case 'Group 2':
      return '2 Digit';
    case 'Group 1':
      return '1 Digit';
    default:
      return group;
  }
}

const List<String> _kPriceListGroupOrder = ['Group 3', 'Group 2', 'Group 1'];

void _attachWinningRowColors(
  Map<String, dynamic> winningRow,
  String suffix,
  String number,
  ResultSnapshot snapshot,
) {
  winningRow['winningDigitTier'] =
      _winningDigitTierForType(winningRow['type']?.toString() ?? '');
  final type = suffix.toUpperCase();
  if (type == 'BOX' ||
      _isOneDigitSchemeSuffix(type) ||
      _isTwoDigitSchemeSuffix(type)) {
    winningRow['winningColorKind'] = 'firstTier';
    winningRow['winningPrizeLabel'] = '1ST PRIZE';
    return;
  }
  if (type != 'SUPER') return;
  final idx = _superPrizeRowIndex(number, snapshot);
  if (idx == null) return;
  if (idx == 5) {
    winningRow['winningColorKind'] = 'compliments';
    winningRow['winningPrizeLabel'] = 'COMPLIMENTS';
  } else {
    winningRow['winningColorKind'] = 'super';
    winningRow['winningPrizeIndex'] = idx;
    winningRow['winningPrizeLabel'] = _prizeTierLabelFromIndex(idx);
  }
}

({
  Color bg,
  Color labelColor,
  Color valueColor,
  Color borderColor,
}) _winningRowPalette(Map<String, dynamic> row) {
  final kind = row['winningColorKind']?.toString();
  if (kind == 'box' || kind == 'firstTier') {
    return (
      bg: _kWinningPrizeLiteColors[0],
      labelColor: Colors.black87,
      valueColor: Colors.black87,
      borderColor: Colors.black26,
    );
  }
  if (kind == 'compliments') {
    return (
      bg: _kComplimentsHeadingBg,
      labelColor: _kComplimentsHeadingGrey,
      valueColor: _kComplimentsHeadingGrey,
      borderColor: _kComplimentBorderColor.withValues(alpha: 0.5),
    );
  }
  if (kind == 'super') {
    final idx = row['winningPrizeIndex'] as int? ?? 0;
    if (idx >= 0 && idx < _kWinningPrizeLiteColors.length) {
      return (
        bg: _kWinningPrizeLiteColors[idx],
        labelColor: Colors.black87,
        valueColor: Colors.black87,
        borderColor: Colors.black26,
      );
    }
  }
  return (
    bg: _winningGreenLight,
    labelColor: _winningGreenDark,
    valueColor: _winningGreen,
    borderColor: _winningGreen.withValues(alpha: 0.18),
  );
}

double _calculateCheckerPrizeAmount(
  Map<String, dynamic> row,
  ResultSnapshot snapshot, {
  required String username,
}) {
  final typeFull = row['type'].toString().toUpperCase();
  final suffix = typeFull.split('-').last;
  final number = _digitsOnly(row['number'].toString());
  final count = int.tryParse(row['count'].toString()) ?? 0;
  if (count <= 0 || number.isEmpty) return 0.0;

  final parts = _calculatePrizeParts(
    suffix,
    number,
    snapshot,
    username,
    includeSuper: false,
  );
  if (parts == null) return 0.0;
  return parts.base * count;
}

double _calculateWinningPrize(
  Map<String, dynamic> row,
  ResultSnapshot snapshot, {
  required String username,
}) {
  final typeFull = row['type'].toString().toUpperCase();
  final suffix = typeFull.split('-').last;
  final number = _digitsOnly(row['number'].toString());
  final count = int.tryParse(row['count'].toString()) ?? 0;
  if (count <= 0 || number.isEmpty) return 0.0;

  final parts = _calculatePrizeParts(
    suffix,
    number,
    snapshot,
    username,
    includeSuper: true,
  );
  if (parts == null) return 0.0;
  return parts.total * count;
}

List<Map<String, dynamic>> _winningRowsForBill(
  BillRecord bill, {
  String drawFilter = "ALL",
}) {
  final drawCode = bill.rows.isNotEmpty
      ? _drawCodeFromType(bill.rows.first["type"].toString())
      : "";
  if (drawCode.isEmpty) return [];
  final String wanted = _drawCodeFromFilter(drawFilter);
  if (wanted.isNotEmpty && drawCode != wanted) return [];
  final snapshot = ResultStore.get(drawCode, _calendarDate(bill.businessDate));
  if (snapshot == null) return [];

  final rows = <Map<String, dynamic>>[];
  for (final row in bill.rows) {
    final typeFull = row['type'].toString().toUpperCase();
    final suffix = typeFull.split('-').last;
    final number = _digitsOnly(row['number'].toString());
    final count = int.tryParse(row['count'].toString()) ?? 0;
    if (count <= 0 || number.isEmpty) continue;

    final parts = _calculatePrizeParts(
      suffix,
      number,
      snapshot,
      bill.username,
      includeSuper: true,
    );
    if (parts == null || parts.total <= 0) continue;

    final scaled = parts.multiply(count);
    final winningRow = Map<String, dynamic>.from(row);
    winningRow['winningWinAmount'] = scaled.base;
    winningRow['winningSuperAmount'] = scaled.superAmount;
    winningRow['winningAmount'] = scaled.total;
    winningRow['winningPrize'] = scaled.total;
    _attachWinningRowColors(winningRow, suffix, number, snapshot);
    rows.add(winningRow);
  }
  rows.sort((a, b) => _winningRowSortKey(a).compareTo(_winningRowSortKey(b)));
  return rows;
}

List<Map<String, dynamic>> _allWinningRowsFromBills(
  List<BillRecord> bills, {
  String drawFilter = 'ALL',
}) {
  final all = <Map<String, dynamic>>[];
  for (final bill in bills) {
    for (final row in _winningRowsForBill(bill, drawFilter: drawFilter)) {
      final enriched = Map<String, dynamic>.from(row);
      enriched['winningBillNo'] = bill.billNo;
      enriched['winningBillUser'] = bill.username;
      enriched['winningBillNote'] = bill.billNote;
      all.add(enriched);
    }
  }
  all.sort((a, b) => _winningRowSortKey(a).compareTo(_winningRowSortKey(b)));
  return all;
}

({double win, double superAmt, double total}) _rangeWinningTotals(
  List<BillRecord> bills, {
  String drawFilter = 'ALL',
}) {
  double win = 0;
  double superAmt = 0;
  for (final bill in bills) {
    for (final r in _winningRowsForBill(bill, drawFilter: drawFilter)) {
      win += BillRecord.winningWinFromRow(r);
      superAmt += BillRecord.winningSuperFromRow(r);
    }
  }
  return (win: win, superAmt: superAmt, total: win + superAmt);
}

/// Fast smooth zoom transition for page navigation.
Route<T> appRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 190),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final scale = Tween<double>(begin: 0.86, end: 1.0).animate(enter);
      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(enter);

      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
      );
    },
  );
}

/// Smooth flowing zoom for dialogs and popups (save confirm, saved bill, etc.).
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    transitionDuration: const Duration(milliseconds: 520),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        reverseCurve: Curves.easeInCubic,
      );
      final scale = Tween<double>(begin: 0.78, end: 1.0).animate(enter);
      final fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.9, curve: Curves.easeOut),
          reverseCurve: const Interval(0.1, 1.0, curve: Curves.easeIn),
        ),
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(enter);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(
            scale: scale,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );
    },
  );
}

void goToMainHome(BuildContext context) {
  final String user =
      AppSession.username.trim().isEmpty ? "admin" : AppSession.username;
  Navigator.pushAndRemoveUntil(
    context,
    appRoute(HomePage(username: user)),
    (route) => false,
  );
}

Future<void> logoutApp(BuildContext context) async {
  await SyncService.clearSession();
  AppSession.username = '';
  AppSession.role = '';
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    appRoute(
      HavellsShellPage(
        onSecretLogin: (ctx) {
          Navigator.push(ctx, appRoute(const LoginPage()));
        },
      ),
    ),
    (route) => false,
  );
}

const Color _kSnackSuccess = Color(0xFF2E7D32);
const Color _kSnackError = Color(0xFFC62828);

void showAppSnack(
  BuildContext context,
  String message, {
  bool success = false,
}) {
  final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        backgroundColor: success ? _kSnackSuccess : _kSnackError,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(12, 0, 12, keyboardBottom + 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 4,
        duration: const Duration(seconds: 3),
      ),
    );
}

void showSuccessSnack(BuildContext context, String message) =>
    showAppSnack(context, message, success: true);

void showErrorSnack(BuildContext context, String message) =>
    showAppSnack(context, message, success: false);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLocale.language,
      builder: (context, lang, _) {
        return ValueListenableBuilder<String>(
          valueListenable: AppDrawTheme.activeDraw,
          builder: (context, draw, __) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: Locale(lang.name),
              theme: ThemeData(
                primaryColor: kAppBlue,
                scaffoldBackgroundColor: Colors.white,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: kAppBlue,
                  primary: kAppBlue,
                  secondary: kAppBlueLight,
                  surface: Colors.white,
                  brightness: Brightness.light,
                ),
                appBarTheme: const AppBarTheme(
                  backgroundColor: kAppBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  surfaceTintColor: Colors.transparent,
                  systemOverlayStyle: SystemUiOverlayStyle(
                    statusBarColor: kAppBlue,
                    statusBarIconBrightness: Brightness.light,
                    statusBarBrightness: Brightness.dark,
                  ),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAppBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
                checkboxTheme: CheckboxThemeData(
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return kAppBlue;
                    return null;
                  }),
                ),
              ),
              home: HavellsShellPage(
                onSecretLogin: (context) {
                  Navigator.push(context, appRoute(const LoginPage()));
                },
              ),
              routes: {
                '/login': (_) => const LoginPage(),
              },
            );
          },
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const Color _havellsRed = Color(0xFFE31E24);

  String username = "";
  String password = "";
  String message = "";
  bool _loading = false;
  bool _obscurePassword = true;

  Future<void> _doLogin() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      message = "";
    });

    try {
      final loginRes = await ApiService.login(
        username: username,
        password: password,
      );
      final userMap = Map<String, dynamic>.from(loginRes['user'] as Map);
      if (userMap['isBlocked'] == true) {
        setState(() {
          message = AppMsg.accountBlocked;
          _loading = false;
        });
        return;
      }

      final uname = userMap['username']?.toString() ?? username;
      final role = userMap['role']?.toString() ?? 'AGENT';
      await SyncService.saveSession(
        token: loginRes['token']?.toString() ?? '',
        username: uname,
        role: role,
      );
      AppSession.username = uname;
      AppSession.role = role;

      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.pushReplacement(
        context,
        appRoute(HomePage(username: uname)),
      );
      schedulePostLoginSync();
    } on ApiException catch (e) {
      final serverUp = await ApiService.healthCheck();
      if (serverUp) {
        setState(() {
          message = AppMsg.cloudLoginFailed(e.message);
          _loading = false;
        });
        return;
      }
      final user = UserStore.authenticate(username, password);
      if (user != null) {
        if (user.isBlocked) {
          setState(() {
            message = AppMsg.accountBlocked;
            _loading = false;
          });
          return;
        }
        AppSession.username = user.username;
        AppSession.role = user.role;
        if (!mounted) return;
        setState(() => _loading = false);
        Navigator.pushReplacement(
          context,
          appRoute(HomePage(username: user.username)),
        );
      } else {
        setState(() {
          message = AppMsg.wrongCredentials;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        message = AppMsg.loginFailed(e);
        _loading = false;
      });
    } finally {
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: _havellsRed,
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Image.asset(
                    'assets/icon/app_icon.png',
                    height: 34,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'HAVELLS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.zero,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF212121),
                            ),
                          ),
                          const SizedBox(height: 28),
                          TextField(
                            onChanged: (value) => username = value,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              prefixIcon: const Icon(Icons.person_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: const BorderSide(
                                  color: _havellsRed,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            obscureText: _obscurePassword,
                            onChanged: (value) => password = value,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_loading) _doLogin();
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: const BorderSide(
                                  color: _havellsRed,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _doLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _havellsRed,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    _havellsRed.withValues(alpha: 0.5),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('SIGN IN'),
                            ),
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFC62828),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _selectedDraw = kDrawTimeNames.first;
  bool _userPickedMenuDraw = false;
  Timer? _menuClockTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDraw = _menuDrawForUser(widget.username);
    AppDrawTheme.refreshForUser(widget.username);
    _menuClockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final autoDraw = _menuDrawForUser(widget.username, at: now);
      setState(() {
        _now = now;
        if (!_userPickedMenuDraw) {
          _selectedDraw = autoDraw;
        } else if (autoDraw == _selectedDraw) {
          _userPickedMenuDraw = false;
        }
      });
      AppDrawTheme.refreshForUser(widget.username, at: now);
    });
  }

  @override
  void dispose() {
    _menuClockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.role == "ADMIN";
    final menuLite = menuDrawLiteColor(_selectedDraw);
    return Scaffold(
      body: Container(
        decoration: _reportPageBgDecoration(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _reportAppBar(widget.username, context, showLogout: true),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _MenuDrawSelector(
                username: widget.username,
                selectedDraw: _selectedDraw,
                now: _now,
                onDrawChanged: (draw) {
                  setState(() {
                    _selectedDraw = draw;
                    _userPickedMenuDraw = true;
                  });
                },
              ),
              const SizedBox(height: 12),
              _simpleMenuCard(
                [
                  _simpleMenuTile(
                    context,
                    rowColor: menuLite,
                    icon: Icons.add_circle_outline,
                    title: 'Add Ticket',
                    onTap: () => _openAddTicket(
                      context,
                      widget.username,
                      _selectedDraw,
                    ),
                  ),
                  _simpleMenuTile(
                    context,
                    rowColor: menuLite,
                    icon: Icons.bar_chart_outlined,
                    title: 'Reports',
                    onTap: () => Navigator.push(
                      context,
                      appRoute(const ReportsPage()),
                    ),
                  ),
                  _simpleMenuTile(
                    context,
                    rowColor: menuLite,
                    icon: Icons.emoji_events_outlined,
                    title: 'Results',
                    onTap: () => Navigator.push(
                      context,
                      appRoute(const DearResultPage()),
                    ),
                  ),
                  _simpleMenuTile(
                    context,
                    rowColor: menuLite,
                    icon: Icons.list_alt_outlined,
                    title: 'Prize And Commission',
                    onTap: () => Navigator.push(
                      context,
                      appRoute(const PriceListPage()),
                    ),
                  ),
                  _simpleMenuTile(
                    context,
                    rowColor: menuLite,
                    icon: Icons.edit_outlined,
                    title: 'Edit / Delete',
                    onTap: () => Navigator.push(
                      context,
                      appRoute(const EditBillPage()),
                    ),
                  ),
                  if (isAdmin)
                    _simpleMenuTile(
                      context,
                      rowColor: menuLite,
                      icon: Icons.filter_3_outlined,
                      title: 'Digit Count Limits',
                      onTap: () => Navigator.push(
                        context,
                        appRoute(const DigitCountLimitsPage()),
                      ),
                    ),
                  if (isAdmin)
                    _simpleMenuTile(
                      context,
                      rowColor: menuLite,
                      icon: Icons.schedule_outlined,
                      title: 'Draw Timings',
                      onTap: () => Navigator.push(
                        context,
                        appRoute(const DrawSchedulePage()),
                      ),
                    ),
                  if (isAdmin)
                    _simpleMenuTile(
                      context,
                      rowColor: menuLite,
                      icon: Icons.people_outline,
                      title: 'Manage Users',
                      onTap: () => Navigator.push(
                        context,
                        appRoute(const ManageUsersPage()),
                      ),
                    ),
                  _simpleMenuTile(
                    context,
                    rowColor: menuLite,
                    icon: Icons.language_outlined,
                    title: AppMsg.menuLanguage,
                    onTap: () => showLanguagePicker(context),
                  ),
                ],
                flat: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _simpleMenuTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required VoidCallback onTap,
  Color? rowColor,
  Color? borderColor,
}) {
  final edge = borderColor ?? Colors.grey.shade400;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: rowColor ?? Colors.transparent,
      border: rowColor != null
          ? Border(
              bottom: BorderSide(color: edge, width: 1.5),
            )
          : null,
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                color: kMenuIconMazha,
                alignment: Alignment.center,
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: kMenuIconMazha),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _simpleMenuCard(
  List<Widget> items, {
  bool flat = true,
}) {
  return Container(
    decoration: const BoxDecoration(
      color: Colors.transparent,
    ),
    clipBehavior: Clip.none,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < items.length; i++) items[i],
      ],
    ),
  );
}

Future<void> showLanguagePicker(BuildContext context) async {
  final current = AppLocale.language.value;
  final picked = await showAppDialog<AppLanguage>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppMsg.languageTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final lang in AppLanguage.values)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                AppLocale.nativeLabel(lang),
                style: TextStyle(
                  fontWeight:
                      lang == current ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: lang == current
                  ? const Icon(Icons.check, color: kAppBlue)
                  : null,
              onTap: () => Navigator.pop(ctx, lang),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(AppMsg.cancel),
        ),
      ],
    ),
  );
  if (picked == null || picked == current) return;
  await AppLocale.setLanguage(picked);
  if (context.mounted) {
    showSuccessSnack(context, AppMsg.languageChanged);
  }
}

const Color _reportBg = kAppSurface;

BoxDecoration _appGradientBox({BorderRadius? radius}) {
  return BoxDecoration(
    color: kAppBlue,
    borderRadius: radius ?? BorderRadius.zero,
  );
}

Decoration _reportPageBgDecoration() {
  return const BoxDecoration(color: kAppSurface);
}

Widget _reportFormCard(Widget child, {bool flat = true}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: child,
  );
}

Widget _appGradientButton({
  required VoidCallback? onPressed,
  required Widget child,
  bool flat = true,
}) {
  const radius = BorderRadius.zero;
  return DecoratedBox(
    decoration: _appGradientBox(radius: radius),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        minimumSize: const Size(double.infinity, 48),
        shape: const RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      child: child,
    ),
  );
}

AppBar _reportAppBar(
  String title,
  BuildContext context, {
  VoidCallback? onBack,
  bool showLogout = false,
  List<Widget>? extraActions,
}) {
  return AppBar(
    leading: onBack != null
        ? IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          )
        : null,
    automaticallyImplyLeading: onBack == null,
    title: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 17,
      ),
    ),
    backgroundColor: kAppBlue,
    foregroundColor: Colors.white,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    iconTheme: const IconThemeData(color: Colors.white),
    actions: [
      if (extraActions != null) ...extraActions,
      IconButton(
        onPressed: () =>
            showLogout ? logoutApp(context) : goToMainHome(context),
        icon: Icon(
          showLogout ? Icons.logout : Icons.home_outlined,
          color: showLogout ? Colors.red : Colors.white,
        ),
        tooltip: showLogout ? 'Logout' : 'Home',
      ),
    ],
  );
}

const Color kDraw1PmColor = Color(0xFF1F4E79); // D1 — deep navy blue
const Color kDraw1PmColorDark = Color(0xFF153A5C);
const Color kDraw3PmColor = Color(0xFFC55A11); // L3 — burnt orange
const Color kDraw3PmColorDark = Color(0xFF9A4310);
const Color kDraw6PmColor = Color(0xFF7030A0); // D6 — plum purple
const Color kDraw6PmColorDark = Color(0xFF552474);
const Color kDraw8PmColor = Color(0xFF385723); // D8 — dark green
const Color kDraw8PmColorDark = Color(0xFF2A4018);

/// App-wide blue / white theme (matches booking page).
const Color kAppBlue = Color(0xFF0B3D7A);
const Color kAppBlueDark = Color(0xFF062952);
const Color kAppBlueLight = Color(0xFF1565C0);
const Color kAppSurface = Color(0xFFF5F8FC);
const List<Color> kAppBlueGradient = [
  kAppBlue,
  kAppBlue,
];

const Color kMenuDrawDear1 = kDraw1PmColor;
const Color kMenuDrawLsk3 = kDraw3PmColor;
const Color kMenuDrawDear6 = kDraw6PmColor;
const Color kMenuDrawDear8 = kDraw8PmColor;

const Color kMenuDrawDear1Lite = Color(0xFFBCD2E8);
const Color kMenuDrawLsk3Lite = Color(0xFFF0D4BC);
const Color kMenuDrawDear6Lite = Color(0xFFE0C8ED);
const Color kMenuDrawDear8Lite = Color(0xFFC8D9BC);

const Color kMenuIconMazha = Color(0xFF51154A);

String menuDrawShortLabel(String draw) {
  switch (draw.trim()) {
    case 'DEAR 1 PM':
      return 'D-1:00PM';
    case 'LSK 3 PM':
      return 'K-3:00PM';
    case 'DEAR 6 PM':
      return 'D-6:00PM';
    case 'DEAR 8 PM':
      return 'D-8:00PM';
    default:
      return draw;
  }
}

Color menuDrawColor(String drawTime) => _drawColorForTime(drawTime);

Color menuDrawLiteColor(String drawTime) => _drawLiteColorForTime(drawTime);

Color _drawLiteColorForTime(String drawTime) {
  switch (drawTime.trim()) {
    case "DEAR 1 PM":
      return kMenuDrawDear1Lite;
    case "LSK 3 PM":
      return kMenuDrawLsk3Lite;
    case "DEAR 6 PM":
      return kMenuDrawDear6Lite;
    case "DEAR 8 PM":
      return kMenuDrawDear8Lite;
    default:
      return kAppBlue.withValues(alpha: 0.12);
  }
}

Color _drawLiteColorForCode(String code) {
  switch (code.toUpperCase()) {
    case "DEAR1":
      return kMenuDrawDear1Lite;
    case "LSK3":
      return kMenuDrawLsk3Lite;
    case "DEAR6":
      return kMenuDrawDear6Lite;
    case "DEAR8":
      return kMenuDrawDear8Lite;
    default:
      return kAppBlue.withValues(alpha: 0.12);
  }
}

Color _drawColorForTime(String drawTime) {
  switch (drawTime.trim()) {
    case "DEAR 1 PM":
      return kMenuDrawDear1;
    case "LSK 3 PM":
      return kMenuDrawLsk3;
    case "DEAR 6 PM":
      return kMenuDrawDear6;
    case "DEAR 8 PM":
      return kMenuDrawDear8;
    default:
      return kAppBlue;
  }
}

Color _drawColorForCode(String code) {
  switch (code.toUpperCase()) {
    case "DEAR1":
      return kMenuDrawDear1;
    case "LSK3":
      return kMenuDrawLsk3;
    case "DEAR6":
      return kMenuDrawDear6;
    case "DEAR8":
      return kMenuDrawDear8;
    default:
      return kAppBlue;
  }
}

Color _drawColorForTypePrefix(String type) {
  final t = type.toUpperCase();
  if (t.startsWith("DEAR1")) return kDraw1PmColor;
  if (t.startsWith("LSK3")) return kDraw3PmColor;
  if (t.startsWith("DEAR6")) return kDraw6PmColor;
  if (t.startsWith("DEAR8")) return kDraw8PmColor;
  return const Color(0xFF546E7A);
}

List<Color> _drawGradientForTime(String drawTime) {
  switch (drawTime.trim()) {
    case "DEAR 1 PM":
      return [kDraw1PmColor, kDraw1PmColorDark];
    case "LSK 3 PM":
      return [kDraw3PmColor, kDraw3PmColorDark];
    case "DEAR 6 PM":
      return [kDraw6PmColor, kDraw6PmColorDark];
    case "DEAR 8 PM":
      return [kDraw8PmColor, kDraw8PmColorDark];
    default:
      final base = _drawColorForTime(drawTime);
      return [base, base];
  }
}

List<Color> _drawLightGradientForTime(String drawTime) {
  final base = _drawColorForTime(drawTime);
  final light = Color.lerp(base, Colors.white, 0.85)!;
  return [light, light];
}

/// Active draw tint for app chrome — follows menu selection or open-time draw.
class AppDrawTheme {
  static final ValueNotifier<String> activeDraw =
      ValueNotifier<String>(kDrawTimeNames.first);

  static void setDraw(String drawTime) {
    final d = drawTime.trim();
    if (d.isEmpty || activeDraw.value == d) return;

    void apply() {
      if (activeDraw.value != d) activeDraw.value = d;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      apply();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    }
  }

  static void refreshForUser(String username, {DateTime? at}) {
    setDraw(
      DrawScheduleStore.currentUiDraw(
        at: at,
        allowed: _allowedDrawsForUser(username),
      ),
    );
  }
}

Color get _appPrimary => kAppBlue;

List<Color> get _appGradient => kAppBlueGradient;

Color get _salesAccent => _appPrimary;

Color _salesDrawColor(String code) => _drawColorForCode(code);

Color _salesDrawTint(String code) =>
    code == 'ALL'
        ? kAppBlue.withValues(alpha: 0.12)
        : _drawLiteColorForCode(code);

String _salesDrawLabel(String code) {
  switch (code) {
    case "DEAR1":
      return "D1";
    case "LSK3":
      return "L3";
    case "DEAR6":
      return "D6";
    case "DEAR8":
      return "D8";
    default:
      return "ALL";
  }
}

String _drawCodeFromRowType(String type) {
  final t = type.toUpperCase();
  if (t.startsWith('LSK3')) return 'LSK3';
  if (t.startsWith('DEAR6')) return 'DEAR6';
  if (t.startsWith('DEAR8')) return 'DEAR8';
  if (t.startsWith('DEAR1')) return 'DEAR1';
  return 'ALL';
}

Color _salesRowTypeColor(String type) =>
    _salesDrawColor(_drawCodeFromRowType(type));

String _salesRowTypeDisplayLabel(String type) {
  final drawCode = _drawCodeFromRowType(type);
  final suffix = schemeSuffixFromName(type).toUpperCase();
  final pm = switch (drawCode) {
    'DEAR1' => '1PM',
    'LSK3' => '3PM',
    'DEAR6' => '6PM',
    'DEAR8' => '8PM',
    _ => '',
  };
  if (pm.isEmpty) return type;
  if (suffix == 'BOX') return 'Box-$pm';
  if (suffix == 'SUPER' || suffix == 'DC') {
    return drawCode == 'LSK3' ? 'K-$pm' : 'DEAR-$pm';
  }
  return '$suffix-$pm';
}

Widget _salesDrawBar({
  required String selected,
  required ValueChanged<String> onChanged,
  bool flat = true,
}) {
  const options = ["ALL", "DEAR1", "LSK3", "DEAR6", "DEAR8"];
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: kAppBlue.withValues(alpha: 0.1),
      border: Border.all(color: Colors.grey.shade300),
    ),
    child: Row(
      children: options.map((d) {
        final sel = d == selected;
        final c = _salesDrawColor(d);
        return Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? c : Colors.transparent,
                ),
                child: Text(
                  _salesDrawLabel(d),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );
}

InputDecoration _salesFieldDecoration(String label, {bool flat = true}) {
  final side = BorderSide(color: Colors.grey.shade300);
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: side),
    enabledBorder:
        OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: side),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: _appPrimary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

Widget _salesStatChip(String label, String value, Color bg) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.14),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: kAppBlue.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

Widget _salesDrawStatChip(String label, String value, Color drawColor) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: drawColor,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: drawColor.withValues(alpha: 0.85)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}

bool _salesRowMatchesDraw(Map<String, dynamic> row, String drawFilter) {
  if (drawFilter == 'ALL') return true;
  return row['type'].toString().startsWith(drawFilter);
}

({int count, double agent, double retail, double commission})
    _salesBillDetailsTotals(
  List<BillRecord> bills, {
  required String drawFilter,
}) {
  int count = 0;
  double agent = 0;
  double retail = 0;
  for (final bill in bills) {
    for (final row in bill.rows) {
      if (!_salesRowMatchesDraw(row, drawFilter)) continue;
      final c = int.tryParse(row['count'].toString()) ?? 0;
      if (c <= 0) continue;
      count += c;
      agent += BillRecord.readRowAmount(row['amount']);
      final scheme = PriceListStore.gameRatesFor(bill.username).billingScheme;
      retail += applyBillingSchemeAmount(
        c * getRetailRate(row['type'].toString()),
        scheme,
      );
    }
  }
  return (
    count: count,
    agent: agent,
    retail: retail,
    commission: retail - agent,
  );
}

const String _kReportAllUsers = 'ALL';

String _defaultReportUserFilter() {
  if (AppSession.role == 'ADMIN') return _kReportAllUsers;
  final u = AppSession.username.trim();
  return u.isEmpty ? _kReportAllUsers : u;
}

List<String> _reportUserFilterOptions(List<AppUser> users) {
  if (AppSession.role != 'ADMIN') {
    final u = AppSession.username.trim();
    return u.isEmpty ? [_kReportAllUsers] : [u];
  }
  final names = users
      .map((u) => u.username.trim())
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return [_kReportAllUsers, ...names];
}

bool _billMatchesReportUserFilter(BillRecord bill, String userFilter) {
  if (userFilter == _kReportAllUsers) return true;
  return bill.username.trim().toLowerCase() ==
      userFilter.trim().toLowerCase();
}

InputDecoration _reportUserFilterDecoration({bool flat = false}) =>
    _salesFieldDecoration('User', flat: flat);

Widget _reportUserFilterDropdown({
  required String value,
  required ValueChanged<String> onChanged,
  bool flat = false,
}) {
  return ValueListenableBuilder<List<AppUser>>(
    valueListenable: UserStore.users,
    builder: (context, users, _) {
      final options = _reportUserFilterOptions(users);
      final selected = options.contains(value) ? value : options.first;
      return DropdownButtonFormField<String>(
        initialValue: selected,
        decoration: _reportUserFilterDecoration(flat: flat),
        items: [
          for (final name in options)
            DropdownMenuItem(
              value: name,
              child: Text(name == _kReportAllUsers ? 'All Users' : name),
            ),
        ],
        onChanged: AppSession.role == 'ADMIN'
            ? (v) => onChanged(v ?? _kReportAllUsers)
            : null,
      );
    },
  );
}

const Color _winningGreen = Color(0xFF2E7D32);
const Color _winningGreenLight = Color(0xFFE8F5E9);
const Color _winningGreenDark = Color(0xFF1B5E20);

/// Lite pastel bands for winning report rows (1st–5th prize).
const List<Color> _kWinningPrizeLiteColors = [
  Color(0xFFBDE8B8), // 1st — lite green
  Color(0xFFB3D4F5), // 2nd — lite blue
  Color(0xFFDCC0E8), // 3rd — lite purple
  Color(0xFFFFD4A8), // 4th — lite orange
  Color(0xFFB8C8E8), // 5th — lite navy
];

const Color _kComplimentsHeadingGrey = Color(0xFF424242);
const Color _kComplimentsHeadingBg = Color(0xFFF5F6F8);

const List<String> _kPrizeTierLabels = [
  '1ST PRIZE',
  '2ND PRIZE',
  '3RD PRIZE',
  '4TH PRIZE',
  '5TH PRIZE',
];

String _prizeTierLabelFromIndex(int index) {
  if (index >= 0 && index < _kPrizeTierLabels.length) {
    return _kPrizeTierLabels[index];
  }
  return '${index + 1}TH PRIZE';
}

String _prizePositionDisplayLabel({
  int? position,
  bool compliments = false,
  bool boxScheme = false,
  bool boxTwoSameDirect = false,
  bool boxTwoSameIndirect = false,
}) {
  if (compliments) return 'COMPLIMENTS';
  if (boxTwoSameDirect) return '2 NO. SAME (DIRECT)';
  if (boxTwoSameIndirect) return '2 NO. SAME (IND)';
  if (boxScheme) return '1ST PRIZE';
  if (position != null && position >= 1 && position <= 5) {
    return _prizeTierLabelFromIndex(position - 1);
  }
  return position?.toString() ?? '';
}

Widget _winningStatChip(String label, String value, Color drawColor) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: drawColor,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: drawColor.withValues(alpha: 0.85)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            '₹$value',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _winningDataColumnsHeader() {
  final labelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: Colors.grey.shade600,
  );
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
    child: Row(
      children: [
        Expanded(flex: 4, child: Text('Prize', style: labelStyle)),
        Expanded(
          flex: 2,
          child: Text('No', textAlign: TextAlign.center, style: labelStyle),
        ),
        SizedBox(
          width: 34,
          child: Text('Qty', textAlign: TextAlign.center, style: labelStyle),
        ),
        SizedBox(
          width: 52,
          child: Text('Win', textAlign: TextAlign.end, style: labelStyle),
        ),
        SizedBox(
          width: 52,
          child: Text('Super', textAlign: TextAlign.end, style: labelStyle),
        ),
        SizedBox(
          width: 58,
          child: Text('Total', textAlign: TextAlign.end, style: labelStyle),
        ),
      ],
    ),
  );
}

Widget _winningDataRow(Map<String, dynamic> row) {
  final winAmt = BillRecord.winningWinFromRow(row);
  final superAmt = BillRecord.winningSuperFromRow(row);
  final totalAmt = BillRecord.winningTotalFromRow(row);
  final palette = _winningRowPalette(row);
  final prizeLabel = row['winningPrizeLabel']?.toString();
  final billNo = row['winningBillNo']?.toString();
  final billUser = row['winningBillUser']?.toString();
  final billNote = row['winningBillNote']?.toString().trim() ?? '';

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: palette.bg,
      border: Border(
        bottom: BorderSide(color: palette.borderColor, width: 0.8),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                prizeLabel ?? row['type'].toString(),
                style: TextStyle(
                  fontSize: prizeLabel != null ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: prizeLabel != null ? 0.35 : 0,
                  color: palette.labelColor,
                ),
              ),
              if (billNo != null && billNo.isNotEmpty)
                Text(
                  'Bill $billNo${billUser != null && billUser.isNotEmpty ? ' · $billUser' : ''}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: palette.labelColor.withValues(alpha: 0.72),
                  ),
                ),
              if (billNote.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Bill Note',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: palette.labelColor.withValues(alpha: 0.65),
                  ),
                ),
                Text(
                  billNote,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: palette.labelColor,
                    height: 1.25,
                  ),
                  softWrap: true,
                ),
              ],
              if (prizeLabel != null)
                Text(
                  row['type'].toString(),
                  style: TextStyle(
                    fontSize: 10,
                    color: palette.labelColor.withValues(alpha: 0.65),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            row['number'].toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.valueColor,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '×${row['count']}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.labelColor.withValues(alpha: 0.9),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '₹${winAmt.toStringAsFixed(0)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.valueColor,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '₹${superAmt.toStringAsFixed(0)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.valueColor,
            ),
          ),
        ),
        SizedBox(
          width: 58,
          child: Text(
            '₹${totalAmt.toStringAsFixed(0)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.valueColor,
            ),
          ),
        ),
      ],
    ),
  );
}

String _winningDigitSectionLabel(int tier) {
  switch (tier) {
    case 3:
      return '3 Digit';
    case 2:
      return '2 Digit';
    case 1:
      return '1 Digit';
    default:
      return '';
  }
}

Widget _winningDigitSectionHeader(String label) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _kComplimentsHeadingBg,
      border: Border(
        bottom: BorderSide(
          color: _kComplimentBorderColor.withValues(alpha: 0.45),
        ),
      ),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: _kComplimentsHeadingGrey,
      ),
    ),
  );
}

List<Widget> _buildGroupedWinningRowWidgets(
  List<Map<String, dynamic>> rows,
) {
  if (rows.isEmpty) return const [];
  final widgets = <Widget>[];
  for (final tier in const [3, 2, 1]) {
    final tierRows = rows
        .where((r) =>
            (r['winningDigitTier'] as int? ??
                _winningDigitTierForType(r['type']?.toString() ?? '')) ==
            tier)
        .toList()
      ..sort((a, b) => _winningRowSortKey(a).compareTo(_winningRowSortKey(b)));
    if (tierRows.isEmpty) continue;
    widgets.add(_winningDigitSectionHeader(_winningDigitSectionLabel(tier)));
    for (final row in tierRows) {
      widgets.add(_winningDataRow(row));
    }
  }
  return widgets;
}

InputDecoration _winningGroupDecoration({bool flat = false}) =>
    _salesFieldDecoration("Group", flat: flat);

InputDecoration _winningModeDecoration({bool flat = false}) =>
    _salesFieldDecoration("Mode", flat: flat);

Widget _reportDateBox(
  BuildContext context, {
  required String label,
  required DateTime value,
  required ValueChanged<DateTime> onChanged,
  bool flat = false,
}) {
  return InkWell(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked != null) onChanged(_calendarDate(picked));
    },
    child: InputDecorator(
      decoration: _salesFieldDecoration(label, flat: flat),
      child: Text(
        "${value.day.toString().padLeft(2, "0")}/${value.month.toString().padLeft(2, "0")}/${value.year}",
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
  );
}

Widget _reportPage({
  required BuildContext context,
  required String title,
  required Widget body,
  VoidCallback? onBack,
}) {
  return Scaffold(
    body: Container(
      decoration: _reportPageBgDecoration(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _reportAppBar(title, context, onBack: onBack),
        body: body,
      ),
    ),
  );
}

Future<void> showBookingWhatsappPhoneEditor(BuildContext context) async {
  final controller =
      TextEditingController(text: BookingContactStore.whatsappPhone.value);
  try {
    final phone = await showAppDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Booking WhatsApp Phone'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: 'e.g. 9876543210',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(AppMsg.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(AppMsg.save),
          ),
        ],
      ),
    );
    if (phone != null) {
      await BookingContactStore.setWhatsappPhone(phone);
      if (context.mounted) {
        showSuccessSnack(context, 'Booking WhatsApp phone saved');
      }
    }
  } finally {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }
}

bool get _showBookingWhatsappRow => AppSession.role == 'ADMIN';

const List<DropdownMenuItem<String>> _winningGroupItems = [
  DropdownMenuItem(value: "Select", child: Text("All")),
  DropdownMenuItem(value: "SUPER", child: Text("SUPER")),
  DropdownMenuItem(value: "BOX", child: Text("BOX")),
  DropdownMenuItem(value: "AB", child: Text("AB")),
  DropdownMenuItem(value: "BC", child: Text("BC")),
  DropdownMenuItem(value: "AC", child: Text("AC")),
  DropdownMenuItem(value: "A", child: Text("A")),
  DropdownMenuItem(value: "B", child: Text("B")),
  DropdownMenuItem(value: "C", child: Text("C")),
];

const List<DropdownMenuItem<String>> _winningModeItems = [
  DropdownMenuItem(value: "Select", child: Text("All")),
  DropdownMenuItem(value: "3", child: Text("3 digit")),
  DropdownMenuItem(value: "2", child: Text("2 digit")),
  DropdownMenuItem(value: "1", child: Text("1 digit")),
];

class _WinningReportEmptyBody extends StatelessWidget {
  const _WinningReportEmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "No winning data",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditUserPage extends StatefulWidget {
  final AppUser user;

  const EditUserPage({super.key, required this.user});

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  static const _roleOptions = ['AGENT', 'SUBAGENT', 'CUSTOMER', 'ADMIN'];
  static const _schemeOptions = [
    'ALL',
    'DEAR 1 PM',
    'LSK 3 PM',
    'DEAR 6 PM',
    'DEAR 8 PM',
  ];

  late final TextEditingController passwordCtrl;
  late final TextEditingController usernameCtrl;
  late final TextEditingController amountCtrl;
  late final TextEditingController d1Ctrl;
  late final TextEditingController d2Ctrl;
  late final TextEditingController d3Ctrl;

  late String nextRole;
  late String nextScheme;
  late String nextRateSetId;
  late bool nextLoginBlocked;
  late bool nextSalesBlocked;
  bool _saving = false;

  bool get _isSelf =>
      widget.user.username.trim().toLowerCase() ==
      AppSession.username.trim().toLowerCase();

  bool get _isAgentRole => nextRole == 'AGENT' || nextRole == 'SUBAGENT';

  bool get _showLimitFields => nextRole != 'ADMIN';

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    nextRole = _roleOptions.contains(user.role.toUpperCase())
        ? user.role.toUpperCase()
        : 'CUSTOMER';
    nextScheme =
        _schemeOptions.contains(user.scheme) ? user.scheme : 'ALL';
    nextRateSetId =
        user.rateSetId.trim().isEmpty ? 'standard' : user.rateSetId;
    nextLoginBlocked = user.isBlocked;
    nextSalesBlocked = user.isSalesBlocked;

    passwordCtrl = TextEditingController();
    usernameCtrl = TextEditingController(text: user.username);
    amountCtrl = TextEditingController(
      text: user.amountLimit > 0 ? '${user.amountLimit}' : '',
    );
    d1Ctrl = TextEditingController(
      text: user.digit1CountLimit > 0 ? '${user.digit1CountLimit}' : '',
    );
    d2Ctrl = TextEditingController(
      text: user.digit2CountLimit > 0 ? '${user.digit2CountLimit}' : '',
    );
    d3Ctrl = TextEditingController(
      text: user.digit3CountLimit > 0 ? '${user.digit3CountLimit}' : '',
    );
  }

  @override
  void dispose() {
    passwordCtrl.dispose();
    usernameCtrl.dispose();
    amountCtrl.dispose();
    d1Ctrl.dispose();
    d2Ctrl.dispose();
    d3Ctrl.dispose();
    super.dispose();
  }

  String _rateSetValue(List<RateSet> rateSets) {
    if (rateSets.isEmpty) return 'standard';
    if (rateSets.any((r) => r.id == nextRateSetId)) return nextRateSetId;
    return rateSets.first.id;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final user = widget.user;
    final rateSetId = _rateSetValue(RateSetStore.sets.value);
    var success = true;

    final newPassword = passwordCtrl.text.trim();
    if (newPassword.isNotEmpty) {
      success = UserStore.setPassword(
        username: user.username,
        newPassword: newPassword,
      );
    }
    if (success && !_isSelf && nextRole != user.role) {
      success = UserStore.updateRole(
        username: user.username,
        newRole: nextRole,
      );
    }
    if (success && (nextRole == 'AGENT' || nextRole == 'SUBAGENT')) {
      success = UserStore.updateAgentSettings(
        username: user.username,
        scheme: nextScheme,
        rateSetId: rateSetId,
      );
    }
    if (success && nextRole != 'ADMIN') {
      success = UserStore.updateUserLimits(
        username: user.username,
        amountLimit: double.tryParse(amountCtrl.text.trim()) ?? 0,
        digit1CountLimit: int.tryParse(d1Ctrl.text.trim()) ?? 0,
        digit2CountLimit: int.tryParse(d2Ctrl.text.trim()) ?? 0,
        digit3CountLimit: int.tryParse(d3Ctrl.text.trim()) ?? 0,
      );
    }
    if (success && !_isSelf) {
      if (nextLoginBlocked != user.isBlocked ||
          nextSalesBlocked != user.isSalesBlocked) {
        success = UserStore.setAccessFlags(
          username: user.username,
          loginBlocked: nextLoginBlocked,
          salesBlocked: nextSalesBlocked,
        );
      }
    }

    if (success) {
      await UserStore.persistNow();
    }

    if (!mounted) return;
    setState(() => _saving = false);
    showAppSnack(
      context,
      success ? AppMsg.userUpdated : AppMsg.updateFailed,
      success: success,
    );
    if (success) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: 'Edit User',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: _reportFormCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kAppBlue,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                readOnly: true,
                controller: usernameCtrl,
                decoration: _salesFieldDecoration('Username').copyWith(
                  filled: true,
                  fillColor: Colors.grey.shade100,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: _salesFieldDecoration('New Password'),
              ),
              if (!_isSelf) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('role-$nextRole'),
                  initialValue: nextRole,
                  decoration: _salesFieldDecoration('User Type'),
                  items: const [
                    DropdownMenuItem(value: 'AGENT', child: Text('Agent')),
                    DropdownMenuItem(
                        value: 'SUBAGENT', child: Text('Sub Agent')),
                    DropdownMenuItem(
                        value: 'CUSTOMER', child: Text('Customer')),
                    DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => nextRole = v);
                  },
                ),
              ],
              if (_isAgentRole) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('scheme-$nextScheme'),
                  initialValue: _schemeOptions.contains(nextScheme)
                      ? nextScheme
                      : 'ALL',
                  decoration: _salesFieldDecoration('Scheme'),
                  items: _schemeOptions
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => nextScheme = v);
                  },
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<List<RateSet>>(
                  valueListenable: RateSetStore.sets,
                  builder: (context, rateSets, _) {
                    final selected = _rateSetValue(rateSets);
                    return DropdownButtonFormField<String>(
                      key: ValueKey('rate-$selected'),
                      initialValue: selected,
                      decoration: _salesFieldDecoration('Price List / Rate Set'),
                      items: rateSets
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.name),
                            ),
                          )
                          .toList(),
                      onChanged: rateSets.isEmpty
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() => nextRateSetId = v);
                            },
                    );
                  },
                ),
              ],
              if (_showLimitFields) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      _salesFieldDecoration('Amount Limit per day'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: d3Ctrl,
                  keyboardType: TextInputType.number,
                  decoration: _salesFieldDecoration(
                      '3 Digit Count Limit'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: d2Ctrl,
                  keyboardType: TextInputType.number,
                  decoration: _salesFieldDecoration(
                      '2 Digit Count Limit'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: d1Ctrl,
                  keyboardType: TextInputType.number,
                  decoration: _salesFieldDecoration(
                      '1 Digit Count Limit'),
                ),
              ],
              if (!_isSelf) ...[
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Login Block'),
                  value: nextLoginBlocked,
                  activeThumbColor: Colors.red.shade700,
                  onChanged: (v) => setState(() => nextLoginBlocked = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sales Block'),
                  value: nextSalesBlocked,
                  activeThumbColor: Colors.orange.shade800,
                  onChanged: (v) => setState(() => nextSalesBlocked = v),
                ),
              ],
              const SizedBox(height: 18),
              _appGradientButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DigitCountLimitsPage extends StatefulWidget {
  const DigitCountLimitsPage({super.key});

  @override
  State<DigitCountLimitsPage> createState() => _DigitCountLimitsPageState();
}

class _DigitCountLimitsPageState extends State<DigitCountLimitsPage> {
  late final TextEditingController _d3Ctrl;
  late final TextEditingController _d2Ctrl;
  late final TextEditingController _d1Ctrl;

  @override
  void initState() {
    super.initState();
    final l = DigitLimitStore.limits.value;
    _d3Ctrl = TextEditingController(
      text: l.digit3CountLimit > 0 ? '${l.digit3CountLimit}' : '',
    );
    _d2Ctrl = TextEditingController(
      text: l.digit2CountLimit > 0 ? '${l.digit2CountLimit}' : '',
    );
    _d1Ctrl = TextEditingController(
      text: l.digit1CountLimit > 0 ? '${l.digit1CountLimit}' : '',
    );
  }

  @override
  void dispose() {
    _d3Ctrl.dispose();
    _d2Ctrl.dispose();
    _d1Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = DigitCountLimits(
      digit3CountLimit: int.tryParse(_d3Ctrl.text.trim()) ?? 0,
      digit2CountLimit: int.tryParse(_d2Ctrl.text.trim()) ?? 0,
      digit1CountLimit: int.tryParse(_d1Ctrl.text.trim()) ?? 0,
    );
    await DigitLimitStore.update(next);
    await SyncService.queueDigitCountLimits(next.toJson());
    if (!mounted) return;
    showSuccessSnack(context, AppMsg.digitLimitsSaved);
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: 'Digit Count Limits',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: _reportFormCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _d3Ctrl,
                keyboardType: TextInputType.number,
                decoration:
                    _salesFieldDecoration('3 Digit Number Count'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _d2Ctrl,
                keyboardType: TextInputType.number,
                decoration:
                    _salesFieldDecoration('2 Digit Number Count'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _d1Ctrl,
                keyboardType: TextInputType.number,
                decoration:
                    _salesFieldDecoration('1 Digit Number Count'),
              ),
              const SizedBox(height: 18),
              _appGradientButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DrawSchedulePage extends StatefulWidget {
  const DrawSchedulePage({super.key});

  @override
  State<DrawSchedulePage> createState() => _DrawSchedulePageState();
}

class _DrawSchedulePageState extends State<DrawSchedulePage> {
  Future<void> _pickTime({
    required DrawSchedule schedule,
    required bool isOpen,
  }) async {
    final initial = isOpen
        ? TimeOfDay(hour: schedule.openHour, minute: schedule.openMinute)
        : TimeOfDay(hour: schedule.closeHour, minute: schedule.closeMinute);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null || !mounted) return;

    final updated = isOpen
        ? schedule.copyWith(openHour: picked.hour, openMinute: picked.minute)
        : schedule.copyWith(
            closeHour: picked.hour, closeMinute: picked.minute);

    await DrawScheduleStore.updateSchedule(updated);
    await SyncService.queueDrawSchedules({
      for (final e in DrawScheduleStore.schedules.value.entries)
        e.key: e.value.toJson(),
    });
    if (mounted) setState(() {});
  }

  Color _drawColor(String name) => _drawColorForTime(name);

  Widget _drawFlatTimeBtn({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    bool showLeftDivider = false,
  }) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border(
            top: BorderSide(color: Colors.grey.shade300),
            left: showLeftDivider
                ? BorderSide(color: Colors.grey.shade300)
                : BorderSide.none,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _drawTimingRow({
    required String name,
    required DrawSchedule schedule,
    required bool openNow,
  }) {
    final color = _drawColor(name);
    final openText =
        formatDrawScheduleTime(schedule.openHour, schedule.openMinute);
    final closeText =
        formatDrawScheduleTime(schedule.closeHour, schedule.closeMinute);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  openNow ? 'OPEN' : 'CLOSED',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: openNow
                        ? const Color(0xFF007E33)
                        : const Color(0xFFCC0000),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _drawFlatTimeBtn(
                label: 'Open $openText',
                onPressed: () => _pickTime(schedule: schedule, isOpen: true),
                color: const Color(0xFF007E33),
              ),
              _drawFlatTimeBtn(
                label: 'Close $closeText',
                onPressed: () => _pickTime(schedule: schedule, isOpen: false),
                color: const Color(0xFFCC0000),
                showLeftDivider: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, DrawSchedule>>(
      valueListenable: DrawScheduleStore.schedules,
      builder: (context, map, _) {
        return _reportPage(
          context: context,
          title: 'Draw Timings',
          body: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            itemCount: kDrawTimeNames.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final name = kDrawTimeNames[index];
              final s = map[name] ?? DrawScheduleStore.scheduleFor(name);
              final openNow =
                  DrawScheduleStore.isDrawBookingOpen(name, at: DateTime.now());
              return _drawTimingRow(
                name: name,
                schedule: s,
                openNow: openNow,
              );
            },
          ),
        );
      },
    );
  }
}

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  int _tabIndex = 0;
  bool _loadingUsers = false;
  final ScrollController _listScrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController amountLimitController = TextEditingController();
  final TextEditingController digit1LimitController = TextEditingController();
  final TextEditingController digit2LimitController = TextEditingController();
  final TextEditingController digit3LimitController = TextEditingController();
  String role = "AGENT";
  String scheme = "ALL";
  String rateSetId = "standard";
  bool loginBlocked = false;
  bool salesBlocked = false;

  static const _schemeOptions = [
    "ALL",
    "DEAR 1 PM",
    "LSK 3 PM",
    "DEAR 6 PM",
    "DEAR 8 PM",
  ];

  List<AppUser> _filterUsers(List<AppUser> users) {
    final q = searchController.text.trim().toLowerCase();
    if (q.isEmpty) return users;
    return users.where((u) {
      return u.username.toLowerCase().contains(q) ||
          _roleLabel(u.role).toLowerCase().contains(q) ||
          u.scheme.toLowerCase().contains(q) ||
          RateSetStore.displayName(u.rateSetId).toLowerCase().contains(q);
    }).toList();
  }

  void _clearSearch() {
    searchController.clear();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshUserList());
    });
  }

  Future<void> _refreshUserList() async {
    if (_loadingUsers) return;
    setState(() => _loadingUsers = true);
    try {
      await UserStore.reloadFromDisk();
      await UserStore.pullUsersFromCloud();
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _openEditUser(AppUser user) async {
    final updated = await Navigator.push<bool>(
      context,
      appRoute(EditUserPage(user: user)),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _confirmDelete(AppUser user) async {
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppMsg.deleteUserTitle),
          content: Text(AppMsg.deleteUserBody(user.username)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppMsg.cancel)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppMsg.delete),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final deleted = UserStore.deleteUser(user.username);
    if (!mounted) return;
    showAppSnack(
      context,
      deleted ? AppMsg.userDeleted : AppMsg.userDeleteFailed,
      success: deleted,
    );
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    searchController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    amountLimitController.dispose();
    digit1LimitController.dispose();
    digit2LimitController.dispose();
    digit3LimitController.dispose();
    super.dispose();
  }

  Widget _buildTabSwitcher() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        children: [
          Expanded(child: _flatTabButton(index: 0, label: 'List Users')),
          Container(width: 1, height: 36, color: Colors.grey.shade300),
          Expanded(child: _flatTabButton(index: 1, label: 'Create User')),
        ],
      ),
    );
  }

  Widget _flatTabButton({required int index, required String label}) {
    final selected = _tabIndex == index;
    return Material(
      color: selected ? kAppBlue.withValues(alpha: 0.1) : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? kAppBlue : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _userTag(String label, Color color) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  Widget _userFlatAction({
    required String label,
    required VoidCallback onPressed,
    required Color color,
    bool showLeftDivider = false,
  }) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border(
            top: BorderSide(color: Colors.grey.shade300),
            left: showLeftDivider
                ? BorderSide(color: Colors.grey.shade300)
                : BorderSide.none,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              height: 38,
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _userActionBar(AppUser u, bool isSelf) {
    final actions = <Widget>[
      _userFlatAction(
        label: 'Edit',
        onPressed: () => _openEditUser(u),
        color: kAppBlue,
      ),
    ];
    if (!isSelf) {
      actions.addAll([
        _userFlatAction(
          label: u.isBlocked ? 'Login On' : 'Login Off',
          onPressed: () {
            UserStore.toggleLoginBlock(u.username);
            setState(() {});
          },
          color: u.isBlocked ? const Color(0xFF007E33) : const Color(0xFFCC0000),
          showLeftDivider: true,
        ),
        _userFlatAction(
          label: u.isSalesBlocked ? 'Sales On' : 'Sales Off',
          onPressed: () {
            UserStore.toggleSalesBlock(u.username);
            setState(() {});
          },
          color: u.isSalesBlocked
              ? const Color(0xFF007E33)
              : const Color(0xFFFF8800),
          showLeftDivider: true,
        ),
        _userFlatAction(
          label: 'Delete',
          onPressed: () => _confirmDelete(u),
          color: const Color(0xFFCC0000),
          showLeftDivider: true,
        ),
      ]);
    }
    return Row(children: actions);
  }

  Widget _buildListUsersTab(List<AppUser> users) {
    final filtered = _filterUsers(users);
    final active = users.where((u) => !u.isBlocked).length;
    final loginBlockedCount = users.where((u) => u.isBlocked).length;
    final salesBlockedCount = users.where((u) => u.isSalesBlocked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Text(
            'Total ${users.length}  ·  OK $active  ·  '
            'Login block $loginBlockedCount  ·  Sales block $salesBlockedCount',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            controller: searchController,
            onChanged: (_) => setState(() {}),
            decoration: _salesFieldDecoration('Search username, role, scheme').copyWith(
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: _clearSearch,
                    )
                  : null,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${filtered.length} user${filtered.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              if (_loadingUsers)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kAppBlue,
                  ),
                )
              else
                TextButton(
                  onPressed: _refreshUserList,
                  style: TextButton.styleFrom(
                    foregroundColor: kAppBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Refresh'),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text(
                          searchController.text.isEmpty
                              ? 'No users yet'
                              : 'No users match your search',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  controller: _listScrollController,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _userCard(filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildCreateUserTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: usernameController,
            decoration: _salesFieldDecoration('Username'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: _salesFieldDecoration('Password'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(role),
            initialValue: role,
            decoration: _salesFieldDecoration('User Type'),
            items: const [
              DropdownMenuItem(value: 'AGENT', child: Text('Agent')),
              DropdownMenuItem(value: 'SUBAGENT', child: Text('Sub Agent')),
            ],
            onChanged: (v) => setState(() => role = v ?? 'AGENT'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(scheme),
            initialValue: scheme,
            decoration: _salesFieldDecoration('Scheme'),
            items: _schemeOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => scheme = v ?? 'ALL'),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<List<RateSet>>(
            valueListenable: RateSetStore.sets,
            builder: (context, rateSets, _) {
              final selected = rateSets.any((r) => r.id == rateSetId)
                  ? rateSetId
                  : (rateSets.isNotEmpty ? rateSets.first.id : 'standard');
              return DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                decoration: _salesFieldDecoration('Price List / Rate Set'),
                items: rateSets
                    .map(
                      (r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.name),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => rateSetId = v ?? rateSetId),
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: amountLimitController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: _salesFieldDecoration('Amount Limit per day'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: digit3LimitController,
                  keyboardType: TextInputType.number,
                  decoration: _salesFieldDecoration('3 Digit Limit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: digit2LimitController,
                  keyboardType: TextInputType.number,
                  decoration: _salesFieldDecoration('2 Digit Limit'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: digit1LimitController,
                  keyboardType: TextInputType.number,
                  decoration: _salesFieldDecoration('1 Digit Limit'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Login Block'),
            value: loginBlocked,
            activeThumbColor: Colors.red.shade700,
            onChanged: (v) => setState(() => loginBlocked = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sales Block'),
            value: salesBlocked,
            activeThumbColor: Colors.orange.shade800,
            onChanged: (v) => setState(() => salesBlocked = v),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: Material(
              color: kAppBlue,
              borderRadius: BorderRadius.zero,
              child: InkWell(
                onTap: _submitCreateUser,
                borderRadius: BorderRadius.zero,
                child: const Center(
                  child: Text(
                    'Create User',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitCreateUser() async {
    if (rateSetId.trim().isEmpty) {
      showErrorSnack(context, AppMsg.selectRateSet);
      return;
    }
    final ok = UserStore.addUser(
      username: usernameController.text,
      password: passwordController.text,
      role: role,
      scheme: scheme,
      rateSetId: rateSetId,
      amountLimit: double.tryParse(amountLimitController.text.trim()) ?? 0,
      digit1CountLimit: int.tryParse(digit1LimitController.text.trim()) ?? 0,
      digit2CountLimit: int.tryParse(digit2LimitController.text.trim()) ?? 0,
      digit3CountLimit: int.tryParse(digit3LimitController.text.trim()) ?? 0,
      isBlocked: loginBlocked,
      isSalesBlocked: salesBlocked,
    );
    if (!ok) {
      if (!mounted) return;
      showErrorSnack(
        context,
        AppMsg.createUserFailed,
      );
      return;
    }

    await UserStore.persistNow();
    await UserStore.pullUsersFromCloud();

    final createdName = usernameController.text.trim();
    usernameController.clear();
    passwordController.clear();
    amountLimitController.clear();
    digit1LimitController.clear();
    digit2LimitController.clear();
    digit3LimitController.clear();
    _clearSearch();

    if (!mounted) return;
    setState(() {
      role = 'AGENT';
      scheme = 'ALL';
      rateSetId = 'standard';
      loginBlocked = false;
      salesBlocked = false;
      _tabIndex = 0;
    });

    if (_listScrollController.hasClients) {
      _listScrollController.jumpTo(0);
    }

    showSuccessSnack(
      context,
      createdName.isEmpty
          ? AppMsg.userCreated
          : AppMsg.userCreatedNamed(createdName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: "Manage Users",
      body: ValueListenableBuilder<List<AppUser>>(
        valueListenable: UserStore.users,
        builder: (context, users, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTabSwitcher(),
              Expanded(
                child: _tabIndex == 0
                    ? _buildListUsersTab(users)
                    : _buildCreateUserTab(),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toUpperCase()) {
      case "ADMIN":
        return kAppBlue;
      case "AGENT":
        return const Color(0xFF0099CC);
      case "SUBAGENT":
        return const Color(0xFF6A1B9A);
      case "CUSTOMER":
        return const Color(0xFF546E7A);
      default:
        return Colors.grey;
    }
  }

  String _roleLabel(String role) {
    final r = role.trim().toUpperCase();
    if (r.isEmpty) return 'User';
    switch (r) {
      case "SUBAGENT":
        return "Sub Agent";
      default:
        return r[0] + r.substring(1).toLowerCase();
    }
  }

  Widget _userCard(AppUser u) {
    final isSelf = u.username.trim().toLowerCase() ==
        AppSession.username.trim().toLowerCase();
    final roleColor = _roleColor(u.role);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.zero,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        u.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelf)
                      Text(
                        'You',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kAppBlue,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _userTag(_roleLabel(u.role), roleColor),
                    if (u.isBlocked)
                      _userTag('Login Block', const Color(0xFFCC0000)),
                    if (u.isSalesBlocked)
                      _userTag('Sales Block', const Color(0xFFFF8800)),
                  ],
                ),
                if (u.isAgentRole) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Scheme: ${u.scheme} · ${RateSetStore.displayName(u.rateSetId)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                if (u.role != 'ADMIN' &&
                    (u.amountLimit > 0 ||
                        u.digit1CountLimit > 0 ||
                        u.digit2CountLimit > 0 ||
                        u.digit3CountLimit > 0)) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (u.amountLimit > 0)
                        'Amt ≤ ${u.amountLimit.toStringAsFixed(0)}',
                      if (u.digit1CountLimit > 0)
                        '1D ≤ ${u.digit1CountLimit}',
                      if (u.digit2CountLimit > 0)
                        '2D ≤ ${u.digit2CountLimit}',
                      if (u.digit3CountLimit > 0)
                        '3D ≤ ${u.digit3CountLimit}',
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _userActionBar(u, isSelf),
        ],
      ),
    );
  }
}

class PriceListPage extends StatefulWidget {
  const PriceListPage({super.key});

  @override
  State<PriceListPage> createState() => _PriceListPageState();
}

class _PrizeCommissionRow {
  final String prize;
  final int rate;
  final int dc;

  const _PrizeCommissionRow(this.prize, this.rate, this.dc);
}

class _PriceListPageState extends State<PriceListPage> {
  static const Color _tableHeaderBg = Color(0xFF8E8E8E);
  static const Color _tableBorder = Color(0xFFD0D0D0);

  String _viewUsername = AppSession.username.isNotEmpty
      ? AppSession.username
      : 'admin';

  List<Map<String, dynamic>> get _activeSchemes =>
      PriceListStore.getUnifiedSchemesForUser(_viewUsername);

  Future<void> _openTableEditor({String? schemeName}) async {
    final changed = await Navigator.push<bool>(
      context,
      appRoute(
        PriceListTableEditorPage(
          username: _viewUsername,
          focusSchemeName: schemeName,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Map<String, dynamic>? _schemeBySuffix(String suffix) {
    final target = 'DEAR1-${suffix.toUpperCase()}';
    for (final s in _activeSchemes) {
      if (s['name']?.toString().toUpperCase() == target) return s;
    }
    return null;
  }

  int _displayDc(List<int> row, _WinningPrizeParts fallback) {
    final superAmt = row.length > 3 ? row[3] : 0;
    if (superAmt > 0) return superAmt;
    return fallback.superAmount.toInt();
  }

  List<_PrizeCommissionRow> _commissionRows() {
    const superLabels = [
      'First',
      'Second',
      'Third',
      'Fourt',
      'Five',
      'Guarantee (Six)',
    ];
    final out = <_PrizeCommissionRow>[];

    final superScheme = _schemeBySuffix('SUPER');
    if (superScheme != null) {
      final rows = coercePrizeRows(superScheme['rows']);
      for (var i = 0; i < rows.length && i < superLabels.length; i++) {
        final row = rows[i];
        final fallback = i < _kSuperRowFallbacks.length
            ? _kSuperRowFallbacks[i]
            : const _WinningPrizeParts(base: 0, superAmount: 0);
        out.add(_PrizeCommissionRow(
          superLabels[i],
          row[2],
          _displayDc(row, fallback),
        ));
      }
    }

    final boxScheme = _schemeBySuffix('BOX');
    if (boxScheme != null) {
      final rows = coercePrizeRows(boxScheme['rows']);
      if (rows.isNotEmpty) {
        out.add(_PrizeCommissionRow(
          'Box First Price',
          rows[0][2],
          _displayDc(rows[0], _kBoxNormalDirectFallback),
        ));
      }
      if (rows.length > 1) {
        out.add(_PrizeCommissionRow(
          'Box Series',
          rows[1][2],
          _displayDc(rows[1], _kBoxNormalIndirectFallback),
        ));
      }
      if (rows.length > 6) {
        out.add(_PrizeCommissionRow(
          'Double Box First Price',
          rows[6][2],
          _displayDc(rows[6], _kBox2SameDirectFallback),
        ));
      }
      if (rows.length > 7) {
        out.add(_PrizeCommissionRow(
          'Double Box Series',
          rows[7][2],
          _displayDc(rows[7], _kBox2SameIndirectFallback),
        ));
      }
    }

    final single = _schemeBySuffix('A');
    if (single != null) {
      final rows = coercePrizeRows(single['rows']);
      if (rows.isNotEmpty) {
        final row = rows.first;
        out.add(_PrizeCommissionRow(
          'Single(1)',
          row[2],
          _displayDc(row, _kAbcFallback),
        ));
      }
    }

    final dbl = _schemeBySuffix('AB');
    if (dbl != null) {
      final rows = coercePrizeRows(dbl['rows']);
      if (rows.isNotEmpty) {
        final row = rows.first;
        out.add(_PrizeCommissionRow(
          'Double(2)',
          row[2],
          _displayDc(row, _k2dFallback),
        ));
      }
    }

    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _commissionRows();

    return _reportPage(
      context: context,
      title: 'Prize And Commission',
      body: ColoredBox(
        color: Colors.white,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
          children: [
            if (AppSession.role == 'ADMIN') ...[
              ValueListenableBuilder<List<AppUser>>(
                valueListenable: UserStore.users,
                builder: (context, users, _) {
                  final names = users.map((u) => u.username).toList();
                  final selected = names.contains(_viewUsername)
                      ? _viewUsername
                      : (names.isNotEmpty ? names.first : 'admin');
                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(selected),
                          initialValue: selected,
                          decoration: _salesFieldDecoration('User'),
                          items: names
                              .map((n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _viewUsername = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Rate Master',
                        onPressed: () {
                          Navigator.push(
                            context,
                            appRoute(UserRateMasterPage(username: selected)),
                          );
                        },
                        icon: Icon(Icons.tune, color: _appGradient.first),
                      ),
                      IconButton(
                        tooltip: 'Edit prize table',
                        onPressed: _openTableEditor,
                        icon: Icon(Icons.table_chart_outlined,
                            color: _appGradient.first),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
            _prizeCommissionTable(rows),
          ],
        ),
      ),
    );
  }

  Widget _prizeCommissionTable(List<_PrizeCommissionRow> rows) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _tableBorder),
      ),
      child: Column(
        children: [
          _prizeCommissionTableRow('Prize', 'Rate', 'DC', header: true),
          for (final row in rows)
            _prizeCommissionTableRow(
              row.prize,
              '${row.rate}',
              '${row.dc}',
            ),
        ],
      ),
    );
  }

  Widget _prizeCommissionTableRow(
    String prize,
    String rate,
    String dc, {
    bool header = false,
  }) {
    final bg = header ? _tableHeaderBg : Colors.white;
    final prizeStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: header ? Colors.white : Colors.black,
    );
    final valueStyle = TextStyle(
      fontSize: 15,
      fontWeight: header ? FontWeight.w700 : FontWeight.w400,
      color: header ? Colors.white : Colors.black,
    );

    Widget cell(String text, TextStyle style, {TextAlign align = TextAlign.left}) {
      return Container(
        alignment: align == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: Border(
            bottom: BorderSide(color: _tableBorder),
            right: BorderSide(color: _tableBorder),
          ),
        ),
        child: Text(text, textAlign: align, style: style),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: cell(prize, prizeStyle)),
          Expanded(flex: 3, child: cell(rate, valueStyle, align: TextAlign.center)),
          Expanded(
            flex: 2,
            child: cell(
              dc,
              valueStyle,
              align: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class PriceListTableEditorPage extends StatefulWidget {
  final String username;
  final String? focusSchemeName;

  const PriceListTableEditorPage({
    super.key,
    required this.username,
    this.focusSchemeName,
  });

  @override
  State<PriceListTableEditorPage> createState() =>
      _PriceListTableEditorPageState();
}

class _PriceListTableEditorPageState extends State<PriceListTableEditorPage> {
  late List<Map<String, dynamic>> _schemes;
  final List<TextEditingController> _rateCtrl = [];
  final List<List<List<TextEditingController>>> _cellCtrl = [];
  bool _saving = false;

  List<int> get _visibleIndices {
    final focus = widget.focusSchemeName?.trim().toUpperCase();
    if (focus == null || focus.isEmpty) {
      return List.generate(_schemes.length, (i) => i);
    }
    final out = <int>[];
    final focusSuffix = schemeSuffixFromName(focus);
    for (var i = 0; i < _schemes.length; i++) {
      final name = _schemes[i]['name']?.toString().toUpperCase() ?? '';
      if (name == focus || schemeSuffixFromName(name) == focusSuffix) {
        out.add(i);
      }
    }
    return out.isEmpty && _schemes.isNotEmpty ? [0] : out;
  }

  @override
  void initState() {
    super.initState();
    _loadSchemes();
  }

  void _loadSchemes() {
    _disposeControllers();
    final raw = PriceListStore.getUnifiedSchemesForUser(widget.username);
    _schemes = raw.map((s) {
      final name = s['name']?.toString() ?? '';
      return {
        'name': name,
        'group': s['group'],
        'rate': coerceSchemeRate(s['rate'], name),
        'rows': coercePrizeRows(s['rows']),
      };
    }).toList();

    _rateCtrl.clear();
    _cellCtrl.clear();

    for (final scheme in _schemes) {
      final rate = readBookingRate(scheme['rate']);
      _rateCtrl.add(TextEditingController(
        text: rate.toStringAsFixed(2),
      ));
      final rows = scheme['rows'] as List<List<int>>;
      final rowCtrls = <List<TextEditingController>>[];
      for (final row in rows) {
        rowCtrls.add([
          TextEditingController(text: '${row[0]}'),
          TextEditingController(text: '${row[1]}'),
          TextEditingController(text: '${row[2]}'),
          TextEditingController(text: '${row[3]}'),
        ]);
      }
      _cellCtrl.add(rowCtrls);
    }
  }

  void _disposeControllers() {
    for (final c in _rateCtrl) {
      c.dispose();
    }
    for (final scheme in _cellCtrl) {
      for (final row in scheme) {
        for (final c in row) {
          c.dispose();
        }
      }
    }
    _rateCtrl.clear();
    _cellCtrl.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  int _readInt(String text, {int fallback = 0}) =>
      int.tryParse(text.trim()) ?? fallback;

  double _readDouble(String text, {double fallback = 0}) =>
      double.tryParse(text.trim()) ?? fallback;

  void _addRow(int schemeIndex) {
    setState(() {
      _cellCtrl[schemeIndex].add([
        TextEditingController(text: '${_cellCtrl[schemeIndex].length + 1}'),
        TextEditingController(text: '1'),
        TextEditingController(text: '0'),
        TextEditingController(text: '0'),
      ]);
    });
  }

  void _removeRow(int schemeIndex, int rowIndex) {
    if (_cellCtrl[schemeIndex].length <= 1) return;
    setState(() {
      for (final c in _cellCtrl[schemeIndex][rowIndex]) {
        c.dispose();
      }
      _cellCtrl[schemeIndex].removeAt(rowIndex);
    });
  }

  List<Map<String, dynamic>> _buildPayload() {
    final out = <Map<String, dynamic>>[];
    for (var si = 0; si < _schemes.length; si++) {
      final rows = <List<int>>[];
      for (final row in _cellCtrl[si]) {
        rows.add([
          _readInt(row[0].text, fallback: 1),
          _readInt(row[1].text, fallback: 1),
          _readInt(row[2].text),
          _readInt(row[3].text),
        ]);
      }
      out.add({
        'name': _schemes[si]['name'],
        'group': _schemes[si]['group'],
        'rate': _readDouble(
          _rateCtrl[si].text,
          fallback: _schemes[si]['rate'] as double,
        ),
        'rows': rows,
      });
    }
    return out;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await PriceListStore.setSchemesForAllDrawsNow(
      widget.username,
      _buildPayload(),
    );
    if (AppSession.role == 'ADMIN') {
      await SyncService.queuePriceList(
        PriceListStore.exportAllSchemes(),
        PriceListStore.exportAllGameRates(),
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showSuccessSnack(
      context,
      AppMsg.prizeTableSaved,
    );
    Navigator.pop(context, true);
  }

  Color _schemeTint(String name) {
    final n = name.toUpperCase();
    if (n.contains('SUPER')) return const Color(0xFF5E35B1);
    if (n.contains('BOX')) return const Color(0xFF00897B);
    if (n.contains('-AB') || n.contains('-BC') || n.contains('-AC')) {
      return const Color(0xFF3949AB);
    }
    return const Color(0xFFE65100);
  }

  Widget _rowField(TextEditingController c, {bool compact = false}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      scrollPhysics: const NeverScrollableScrollPhysics(),
      style: TextStyle(fontSize: compact ? 13 : 14),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 6,
          vertical: compact ? 8 : 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  Widget _schemeEditor(int index) {
    final scheme = _schemes[index];
    final name = scheme['name']?.toString() ?? '';
    final tint = _schemeTint(name);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.layers_outlined, color: tint, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        scheme['group']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rateCtrl[index],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              scrollPhysics: const NeverScrollableScrollPhysics(),
              decoration: _salesFieldDecoration('Custom scheme rate'),
            ),
            const SizedBox(height: 10),
            Row(
              children: const [
                Expanded(
                  child: Text('Position',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text('Count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text('Amount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text('Super',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                SizedBox(width: 36),
              ],
            ),
            const SizedBox(height: 6),
            for (var ri = 0; ri < _cellCtrl[index].length; ri++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _rowField(_cellCtrl[index][ri][0])),
                  const SizedBox(width: 6),
                  Expanded(child: _rowField(_cellCtrl[index][ri][1])),
                  const SizedBox(width: 6),
                  Expanded(child: _rowField(_cellCtrl[index][ri][2])),
                  const SizedBox(width: 6),
                  Expanded(child: _rowField(_cellCtrl[index][ri][3])),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove row',
                    onPressed: _cellCtrl[index].length > 1
                        ? () => _removeRow(index, ri)
                        : null,
                    icon: Icon(Icons.remove_circle_outline,
                        size: 20, color: Colors.red.shade300),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _addRow(index),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add row'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: 'Edit Prize Table',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          Text(
            widget.username,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          for (final index in _visibleIndices) _schemeEditor(index),
          const SizedBox(height: 8),
          _appGradientButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Prize Table'),
          ),
        ],
      ),
    );
  }
}

class UserRateMasterPage extends StatefulWidget {
  final String username;

  const UserRateMasterPage({super.key, required this.username});

  @override
  State<UserRateMasterPage> createState() => _UserRateMasterPageState();
}

class _UserRateMasterPageState extends State<UserRateMasterPage> {
  late UserGameRates _rates;
  final Map<String, TextEditingController> _ctrl = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rates = PriceListStore.gameRatesFor(widget.username);
    for (final entry in {
      'superDcRate': _rates.superDcRate,
      'rateD1': _rates.unifiedD1,
      'rateD2': _rates.unifiedD2,
      'rateD3': _rates.unifiedD3,
    }.entries) {
      _ctrl[entry.key] = TextEditingController(
        text: entry.value > 0 ? '${entry.value}' : '',
      );
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _read(String key) => double.tryParse(_ctrl[key]?.text.trim() ?? '') ?? 0;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await PriceListStore.setUnifiedGameRatesForUser(
      widget.username,
      superDcRate: _read('superDcRate'),
      d1: _read('rateD1'),
      d2: _read('rateD2'),
      d3: _read('rateD3'),
      billingScheme: _rates.billingScheme,
    );
    if (AppSession.role == 'ADMIN') {
      await SyncService.queuePriceList(
        PriceListStore.exportAllSchemes(),
        PriceListStore.exportAllGameRates(),
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showSuccessSnack(
      context,
      AppMsg.ratesSaved,
    );
    Navigator.pop(context, true);
  }

  Widget _rateField(String label, String key) {
    return TextField(
      controller: _ctrl[key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _salesFieldDecoration(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: 'Rate Master',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: _reportFormCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.username,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    appRoute(
                      PriceListTableEditorPage(
                        username: widget.username,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Edit Prize Table (Amount / Super)'),
              ),
              const SizedBox(height: 14),
              _rateField('SUPER/DC Rate', 'superDcRate'),
              const SizedBox(height: 10),
              _rateField('1D Rate — A/B/C', 'rateD1'),
              _rateField('2D Rate — AB/BC/AC', 'rateD2'),
              _rateField('3D Rate — SUPER/BOX/DC', 'rateD3'),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                key: ValueKey(_rates.billingScheme),
                initialValue: _rates.billingScheme.clamp(1, 4),
                decoration: _salesFieldDecoration('Billing Scheme'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 — 100%')),
                  DropdownMenuItem(value: 2, child: Text('2 — 75%')),
                  DropdownMenuItem(value: 3, child: Text('3 — 50%')),
                  DropdownMenuItem(value: 4, child: Text('4 — 25%')),
                ],
                onChanged: (v) =>
                    setState(() => _rates.billingScheme = v ?? 1),
              ),
              const SizedBox(height: 18),
              _appGradientButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Save Rates'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lottery-style result screen (reference layout: draw, prize rows, compliments grid).
const List<double> _kResultPrizeFontSizes = [22, 20, 18, 16, 14];

final List<TextInputFormatter> _kResultNumberInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(3),
];

String _normalizeResultNumber(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '---';
  return digits.length > 3 ? digits.substring(0, 3) : digits;
}

/// 1st prize: always last 3 digits (display + storage).
String _firstPrizeLast3(String raw) {
  if (raw.trim().isEmpty || raw.trim() == '---') return '---';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '---';
  if (digits.length <= 3) return digits.padLeft(3, '0');
  return digits.substring(digits.length - 3);
}

String _formatComplimentDisplay(String raw) {
  if (raw.trim().isEmpty || raw.trim() == '---') return '---';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '---';
  final n = int.tryParse(digits.length > 3 ? digits.substring(0, 3) : digits);
  if (n == null) return '---';
  return n.toString().padLeft(3, '0');
}

/// Smallest→largest, column1 (0–9), then column2, then column3.
List<String> _sortedComplimentsColumnMajor(List<String> raw) {
  final numbers = <int>[];
  for (final item in raw) {
    if (item.trim().isEmpty || item.trim() == '---') continue;
    final digits = item.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) continue;
    final n = int.tryParse(
      digits.length > 3 ? digits.substring(digits.length - 3) : digits,
    );
    if (n != null) numbers.add(n);
  }
  numbers.sort();
  final out = List<String>.filled(30, '---');
  for (int i = 0; i < numbers.length && i < 30; i++) {
    out[i] = numbers[i].toString().padLeft(3, '0');
  }
  return out;
}

List<String> sortedComplimentsColumnMajor(List<String> raw) =>
    _sortedComplimentsColumnMajor(raw);

String formatComplimentDisplay(String raw) => _formatComplimentDisplay(raw);

const int _kComplimentRows = 10;
const int _kComplimentCols = 3;
const Color _kComplimentBorderColor = Color(0xFF9E9E9E);
const double _kComplimentBorderWidth = 0.8;

/// Column layout: col1 top→bottom (0–9), then col2 (10–19), col3 (20–29).
int _complimentCellIndex(int row, int col) =>
    col * _kComplimentRows + row;

Widget _buildComplimentsThreeColumns({
  required double fontSize,
  required List<String> values,
  List<TextEditingController>? controllers,
  List<FocusNode>? focusNodes,
  int focusFieldOffset = 0,
  void Function(int storageIndex, String value)? onFieldChanged,
  void Function(TextEditingController controller)? onFieldTap,
}) {
  final editing = controllers != null;

  return Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: List.generate(_kComplimentCols, (col) {
      return Expanded(
        child: Container(
          decoration: BoxDecoration(
            border: col < _kComplimentCols - 1
                ? const Border(
                    right: BorderSide(
                      color: _kComplimentBorderColor,
                      width: _kComplimentBorderWidth,
                    ),
                  )
                : null,
          ),
          child: Column(
          children: List.generate(_kComplimentRows, (row) {
            final storageIndex = _complimentCellIndex(row, col);
            final raw = storageIndex < values.length ? values[storageIndex] : '---';
            final display = _formatComplimentDisplay(raw);

            return Expanded(
              child: Center(
                child: editing
                    ? TextField(
                        controller: controllers![storageIndex],
                        focusNode: focusNodes?[focusFieldOffset + storageIndex],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        textInputAction: storageIndex == 29
                            ? TextInputAction.done
                            : TextInputAction.next,
                        inputFormatters: _kResultNumberInputFormatters,
                        onTap: () => onFieldTap?.call(controllers[storageIndex]),
                        onChanged: (v) =>
                            onFieldChanged?.call(storageIndex, v),
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A),
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          hintText: '---',
                        ),
                      )
                    : Text(
                        display,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
              ),
            );
          }),
        ),
        ),
      );
    }),
  );
}

Widget _buildComplimentsBlock({required Widget grid}) {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(
        color: _kComplimentBorderColor,
        width: _kComplimentBorderWidth,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: _kComplimentBorderColor,
                width: _kComplimentBorderWidth,
              ),
            ),
          ),
          child: Text(
            "COMPLIMENTS",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              letterSpacing: 0.8,
              fontWeight: FontWeight.bold,
              color: _kComplimentsHeadingGrey,
            ),
          ),
        ),
        Expanded(child: grid),
      ],
    ),
  );
}

class EditDearResultPage extends StatefulWidget {
  final String selectedDraw;
  final DateTime resultDate;
  final String drawCode;
  final List<String> initialPrizes;
  final List<String> initialCompliments;

  const EditDearResultPage({
    super.key,
    required this.selectedDraw,
    required this.resultDate,
    required this.drawCode,
    required this.initialPrizes,
    required this.initialCompliments,
  });

  @override
  State<EditDearResultPage> createState() => _EditDearResultPageState();
}

class _EditDearResultPageState extends State<EditDearResultPage> {
  static const int _prizeFieldCount = 5;
  static const int _complimentFieldCount = 30;

  late final List<TextEditingController> _prizeControllers;
  late final List<TextEditingController> _complimentControllers;
  final List<FocusNode> _focusNodes = List.generate(
    _prizeFieldCount + _complimentFieldCount,
    (_) => FocusNode(),
  );

  String _drawDisplayTitle(String draw) => draw.replaceAll(" PM", "PM");

  Color _drawThemeColor(String draw) => _drawColorForTime(draw);

  List<Color> _drawThemeGradient(String draw) => _drawGradientForTime(draw);

  String _dateLine() {
    final d = widget.resultDate;
    return "${d.day.toString().padLeft(2, "0")}-${d.month.toString().padLeft(2, "0")}-${d.year}";
  }

  @override
  void initState() {
    super.initState();
    _prizeControllers = List.generate(
      5,
      (i) => TextEditingController(
        text: i < widget.initialPrizes.length &&
                widget.initialPrizes[i] != "---"
            ? (i == 0
                ? _firstPrizeLast3(widget.initialPrizes[i])
                : widget.initialPrizes[i])
            : "",
      ),
    );
    final sortedCompliments =
        _sortedComplimentsColumnMajor(widget.initialCompliments);
    _complimentControllers = List.generate(
      30,
      (i) {
        final formatted = _formatComplimentDisplay(sortedCompliments[i]);
        return TextEditingController(
          text: formatted == '---' ? '' : formatted,
        );
      },
    );
    for (int i = 0; i < _prizeFieldCount; i++) {
      _wireAutoSelect(_focusNodes[i], _prizeControllers[i]);
    }
    for (int i = 0; i < _complimentFieldCount; i++) {
      _wireAutoSelect(
        _focusNodes[_complimentFieldIndex(i)],
        _complimentControllers[i],
      );
    }
  }

  int _complimentFieldIndex(int complimentIndex) =>
      _prizeFieldCount + complimentIndex;

  void _selectFieldTextIfPresent(TextEditingController controller) {
    final text = controller.text;
    if (text.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  void _wireAutoSelect(FocusNode node, TextEditingController controller) {
    node.addListener(() {
      if (node.hasFocus) {
        _selectFieldTextIfPresent(controller);
      }
    });
  }

  void _focusNextField(int currentIndex) {
    final next = currentIndex + 1;
    if (next >= _focusNodes.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNodes[next].requestFocus();
    });
  }

  void _onResultFieldChanged(int fieldIndex, String value) {
    if (value.length >= 3) {
      _focusNextField(fieldIndex);
    }
  }

  List<TextInputFormatter> _prizeInputFormatters(int prizeIndex) {
    return _kResultNumberInputFormatters;
  }

  String _normalizePrizeForSave(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '---';
    if (index == 0) return _firstPrizeLast3(digits);
    if (digits.length <= 3) return digits.padLeft(3, '0');
    return digits.substring(digits.length - 3);
  }

  @override
  void dispose() {
    for (final c in _prizeControllers) {
      c.dispose();
    }
    for (final c in _complimentControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _save() {
    final prizes = List.generate(
      5,
      (i) => _normalizePrizeForSave(i, _prizeControllers[i].text),
    );
    final compliments = widget.drawCode.trim().toUpperCase() == 'LSK3'
        ? complimentsAscendingOrder(
            _complimentControllers.map((c) => _normalizeResultNumber(c.text)),
          )
        : _sortedComplimentsColumnMajor(
            _complimentControllers.map((c) => _normalizeResultNumber(c.text)).toList(),
          );

    ResultStore.saveManual(ResultSnapshot(
      drawCode: widget.drawCode,
      date: widget.resultDate,
      prizes: prizes,
      compliments: compliments,
    ));

    final code = widget.drawCode.trim().toUpperCase();
    if (DearAutoResultService.isDearDraw(code)) {
      unawaited(ResultStore.refreshDearDraw(code, widget.resultDate));
    }

    if (!mounted) return;
    showSuccessSnack(context, AppMsg.manualResultSaved);
    Navigator.pop(context, true);
  }

  Future<void> _confirmDelete() async {
    final code = widget.drawCode.trim().toUpperCase();
    final existing = ResultStore.get(code, widget.resultDate);
    if (existing == null) {
      showErrorSnack(context, AppMsg.noResultToDelete);
      return;
    }

    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppMsg.deleteResultTitle),
        content: Text(
          AppMsg.deleteResultBody(
            _drawDisplayTitle(widget.selectedDraw),
            _dateLine(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppMsg.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppMsg.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    ResultStore.remove(code, widget.resultDate);
    if (!mounted) return;
    showSuccessSnack(context, AppMsg.resultDeleted);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kResultClassicHeaderBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          "Manual · ${resultDrawSpacedTime(widget.selectedDraw)}",
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          if (ResultStore.get(widget.drawCode, widget.resultDate) != null)
            TextButton(
              onPressed: _confirmDelete,
              child: const Text(
                'DELETE',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "CANCEL",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kResultClassicHeaderBlue,
              ),
              child: const Text("SAVE"),
            ),
          ),
        ],
      ),
      body: ResultPageTemplateBackground(
        child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: ResultWinningNumbersSearchRow(
                timeLabel: resultDrawCompactTime(widget.selectedDraw),
                dateLabel: resultDateFieldLabel(widget.resultDate),
              ),
            ),
            if (_showBookingWhatsappRow)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: ValueListenableBuilder<String>(
                  valueListenable: BookingContactStore.whatsappPhone,
                  builder: (context, phone, _) {
                    return ResultResultsTitleBar(
                      bookingWhatsappPhone: phone,
                    );
                  },
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: LayoutBuilder(
                  builder: (context, inner) {
                    const double gapLabel = 4;
                    const double prizeFraction = 0.37;

                    final double avail = inner.maxHeight - gapLabel;
                    final double prizeH =
                        (avail * prizeFraction).clamp(0.0, double.infinity);
                    final double complimentsAreaH =
                        (avail - prizeH).clamp(0.0, double.infinity);
                    final double rowFontSize = complimentsAreaH > 0
                        ? (complimentsAreaH / 10 * 0.52).clamp(10.0, 14.0)
                        : 13.0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: prizeH,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: List.generate(5, (i) {
                              return Expanded(
                                child: ResultTemplatePrizeBandField(
                                  prizeIndex: i,
                                  controller: _prizeControllers[i],
                                  focusNode: _focusNodes[i],
                                  numberFontSize: kResultTemplatePrizeFontSizes[i],
                                  inputFormatters: _prizeInputFormatters(i),
                                  onTap: () =>
                                      _selectFieldTextIfPresent(_prizeControllers[i]),
                                  onChanged: (value) =>
                                      _onResultFieldChanged(i, value),
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: gapLabel),
                        Expanded(
                          child: ResultTemplateComplimentsCard(
                            grid: buildResultTemplateComplimentsGrid(
                              fontSize: rowFontSize,
                              values: List.generate(
                                30,
                                (i) => _complimentControllers[i].text,
                              ),
                              controllers: _complimentControllers,
                              focusNodes: _focusNodes,
                              focusFieldOffset: _prizeFieldCount,
                              inputFormatters: _kResultNumberInputFormatters,
                              onFieldChanged: (storageIndex, value) =>
                                  _onResultFieldChanged(
                                    _complimentFieldIndex(storageIndex),
                                    value,
                                  ),
                              onFieldTap: _selectFieldTextIfPresent,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class DearResultPage extends StatefulWidget {
  const DearResultPage({super.key});

  @override
  State<DearResultPage> createState() => _DearResultPageState();
}

class _DearResultPageState extends State<DearResultPage> {
  static const Color _defaultBlue = Color(0xFF1A237E);

  static const List<String> _draws = [
    "DEAR 1 PM",
    "LSK 3 PM",
    "DEAR 6 PM",
    "DEAR 8 PM",
  ];

  String _selectedDraw = "DEAR 1 PM";
  DateTime _resultDate = calendarTodayInIndia();
  String _lastResultSignature = '';
  Timer? _cloudPollTimer;
  bool _fetchingCloud = false;
  final ScreenshotController _shareCaptureController = ScreenshotController();

  /// Prize values — replace with API later; default **---** when no data.
  final List<String> _prizeValues = List<String>.filled(5, "---");

  /// Compliment cells (3×10) — default **---** when no data.
  final List<String> _complimentValues = List<String>.filled(30, "---");

  bool get _canEditResult => AppSession.role == 'ADMIN';

  bool get _isToday => isSameBusinessDate(_resultDate, calendarTodayInIndia());

  /// Matches reference labels: `DEAR 1 PM` → `DEAR 1PM`.
  String _drawDisplayTitle(String draw) => draw.replaceAll(" PM", "PM");

  Color _drawThemeColor(String draw) {
    if (const [
      "DEAR 1 PM",
      "LSK 3 PM",
      "DEAR 6 PM",
      "DEAR 8 PM",
    ].contains(draw)) {
      return _drawColorForTime(draw);
    }
    return _defaultBlue;
  }

  List<Color> _drawThemeGradient(String draw) {
    if (const [
      "DEAR 1 PM",
      "LSK 3 PM",
      "DEAR 6 PM",
      "DEAR 8 PM",
    ].contains(draw)) {
      return _drawGradientForTime(draw);
    }
    return const [Color(0xFF1A237E), Color(0xFF0D1B66)];
  }

  String _dateLine() {
    final d = _resultDate;
    return "${d.day.toString().padLeft(2, "0")}-${d.month.toString().padLeft(2, "0")}-${d.year}";
  }

  String _currentDrawCode() => _drawCodeFromFilter(_selectedDraw);

  void _applySnapshotToUi(ResultSnapshot? snapshot) {
    if (snapshot == null) {
      for (int i = 0; i < _prizeValues.length; i++) {
        _prizeValues[i] = "---";
      }
      for (int i = 0; i < _complimentValues.length; i++) {
        _complimentValues[i] = "---";
      }
      return;
    }
    final expectedCode = _currentDrawCode();
    if (snapshot.drawCode.trim().toUpperCase() != expectedCode) {
      return;
    }
    for (int i = 0; i < 5; i++) {
      final raw = i < snapshot.prizes.length ? snapshot.prizes[i] : "---";
      _prizeValues[i] = i == 0 ? _firstPrizeLast3(raw) : raw;
    }
    final compl = List<String>.filled(30, '---');
    for (int i = 0; i < 30; i++) {
      compl[i] =
          i < snapshot.compliments.length ? snapshot.compliments[i] : '---';
    }
    final sorted = expectedCode == 'LSK3'
        ? KeralaComplimentRules.forDisplay(compl)
        : _sortedComplimentsColumnMajor(compl);
    for (int i = 0; i < 30; i++) {
      _complimentValues[i] = sorted[i];
    }
  }

  void _loadSavedResult() {
    if (!mounted) return;
    final code = _currentDrawCode();
    if (code.isEmpty) return;
    final snapshot = ResultStore.get(code, _resultDate);
    if (snapshot != null &&
        snapshot.drawCode.trim().toUpperCase() != code) {
      return;
    }
    final sig = ResultStore.signature(snapshot);
    if (sig == _lastResultSignature) return;
    _lastResultSignature = sig;
    setState(() => _applySnapshotToUi(snapshot));
  }

  void _clearResultUi() {
    _lastResultSignature = '';
    if (!mounted) return;
    setState(() => _applySnapshotToUi(null));
  }

  Future<void> _refreshCurrentDrawResult({bool userTriggered = false}) async {
    if (!mounted || _fetchingCloud) return;
    if (!mounted) return;
    setState(() => _fetchingCloud = true);
    try {
      if (_currentDrawCode() == 'LSK3' && _isToday) {
        await _refreshKeralaFromNet(
          _resultDate,
          userTriggered: userTriggered,
          forceOverwrite: userTriggered,
        );
        if (!mounted) return;
        _lastResultSignature = '';
        _loadSavedResult();
      } else {
        await _refreshActiveLiveDraws();
      }
      if (!mounted || !userTriggered) return;
      final code = _currentDrawCode();
      final after = ResultStore.signature(ResultStore.get(code, _resultDate));
      if (after.isEmpty) {
        showErrorSnack(context, AppMsg.resultNotPublished);
      } else if (ResultStore.isComplete(ResultStore.get(code, _resultDate))) {
        showSuccessSnack(context, AppMsg.resultUpdated);
      } else {
        showSuccessSnack(context, AppMsg.partialResultLoaded);
      }
    } catch (e) {
      if (userTriggered && mounted) {
        showErrorSnack(context, AppMsg.fetchFailed(e));
      }
    } finally {
      if (mounted) setState(() => _fetchingCloud = false);
    }
  }

  Future<void> _refreshActiveLiveDraws() async {
    if (!mounted) return;
    final now = DearAutoResultService.nowInIndia();
    final inLive = ResultFetchService.isAnyLiveWindowActive(now);
    final inFullPush = ResultFetchService.isAnyFullResultPushActive(now);
    final codes = (inLive || inFullPush)
        ? ResultFetchService.kTodayDrawCodes
        : [_currentDrawCode()];

    for (final code in codes) {
      final windowActive = ResultFetchService.isInLiveWindow(code, now) ||
          ResultFetchService.isInFullResultPush(code, now);
      if ((inLive || inFullPush) && !windowActive) {
        continue;
      }
      final existing = ResultStore.get(code, _resultDate);
      if (ResultStore.isComplete(existing) &&
          !ResultFetchService.isInFullResultPush(code, now) &&
          !ResultStore.isManualOverride(code, _resultDate)) {
        continue;
      }
      await ResultStore.refreshDraw(
        code,
        _resultDate,
        fromWeb: true,
        fromCloud: !(inLive || inFullPush) && ApiService.token != null,
      );
      if (!mounted) return;
    }
    if (!mounted) return;
    _lastResultSignature = '';
    _loadSavedResult();
  }

  Future<void> _loadSavedResultFromWeb({bool userTriggered = false}) async {
    await _refreshCurrentDrawResult(userTriggered: userTriggered);
  }

  Future<void> _loadSavedResultFromCloud({bool userTriggered = false}) async {
    if (!mounted || _fetchingCloud) return;
    if (ApiService.token == null) {
      if (userTriggered && mounted) {
        showErrorSnack(context, AppMsg.notSignedIn);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _fetchingCloud = true);
    try {
      final before = ResultStore.signature(
        ResultStore.get(_currentDrawCode(), _resultDate),
      );
      await ResultStore.loadOne(_currentDrawCode(), _resultDate);
      if (!mounted) return;
      final after = ResultStore.signature(
        ResultStore.get(_currentDrawCode(), _resultDate),
      );
      _lastResultSignature = '';
      _loadSavedResult();
      if (!mounted || !userTriggered) return;
      if (after.isEmpty) {
        showErrorSnack(context, AppMsg.resultNotReadyOnServer);
      } else if (after != before) {
        showSuccessSnack(context, AppMsg.resultUpdatedFromCloud);
      } else if (ResultStore.isComplete(
        ResultStore.get(_currentDrawCode(), _resultDate),
      )) {
        showSuccessSnack(context, AppMsg.resultAlreadyComplete);
      } else {
        showSuccessSnack(context, AppMsg.partialResultLoaded);
      }
    } catch (e) {
      if (userTriggered && mounted) {
        showErrorSnack(context, AppMsg.fetchFailed(e));
      }
    } finally {
      if (mounted) setState(() => _fetchingCloud = false);
    }
  }

  void _kickAutoFetchIfNeeded() {
    _stopCloudPoll();
    if (!mounted || !_isToday) return;

    unawaited(_refreshActiveLiveDraws());
    if (!mounted) return;
    _scheduleResultPoll();
  }

  void _scheduleResultPoll() {
    _cloudPollTimer?.cancel();
    if (!mounted || !_isToday) return;

    final now = DateTime.now();
    final allDone = ResultFetchService.kTodayDrawCodes.every((code) {
      if (!ResultStore.isManualOverride(code, _resultDate)) {
        return ResultStore.isComplete(ResultStore.get(code, _resultDate));
      }
      final snap = ResultStore.get(code, _resultDate);
      if (snap == null) return false;
      for (var i = 1; i < 5; i++) {
        if (i >= snap.prizes.length || snap.prizes[i].trim().isEmpty ||
            snap.prizes[i] == '---') {
          return false;
        }
      }
      return snap.compliments.any(
        (c) => c.trim().isNotEmpty && c != '---',
      );
    });
    if (allDone) return;

    final interval = ResultFetchService.pollIntervalFor(
      _currentDrawCode(),
      now,
    );

    _cloudPollTimer = Timer(interval, () {
      if (!mounted || !_isToday) {
        _stopCloudPoll();
        return;
      }
      unawaited(_refreshActiveLiveDraws().then((_) {
        if (mounted) _scheduleResultPoll();
      }));
    });
  }

  void _stopCloudPoll() {
    _cloudPollTimer?.cancel();
    _cloudPollTimer = null;
  }

  Future<void> _bootstrapResultView() async {
    if (!mounted) return;
    _loadSavedResult();
    await ResultStore.refreshDraw(
      _currentDrawCode(),
      _resultDate,
      fromWeb: true,
      fromCloud: ApiService.token != null,
    );
    if (!mounted) return;
    _lastResultSignature = '';
    _loadSavedResult();
    if (!mounted) return;
    _kickAutoFetchIfNeeded();
  }

  void _onDrawOrDateChanged() {
    _clearResultUi();
    _kickAutoFetchIfNeeded();
    unawaited(
      ResultStore.refreshDraw(
        _currentDrawCode(),
        _resultDate,
        fromWeb: true,
        fromCloud: ApiService.token != null,
      ).then((_) {
        if (!mounted) return;
        _lastResultSignature = '';
        _loadSavedResult();
      }),
    );
  }

  void _onResultStoreChanged() {
    if (!mounted) return;
    final code = _currentDrawCode();
    if (code.isEmpty) return;
    _loadSavedResult();
  }

  Future<void> _openLiveYoutube() async {
    final code = _currentDrawCode();
    if (code.isEmpty) return;
    final uri = LotteryLiveLinks.liveUriForDraw(code);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      showErrorSnack(context, AppMsg.liveStreamOpenFailed);
    }
  }

  String _buildShareText() {
    final time = resultDrawSpacedTime(_selectedDraw);
    final date = resultDateIso(_resultDate);
    final buf = StringBuffer('Results $time-$date\n\n');
    for (var i = 0; i < 5; i++) {
      final label = i < kResultTemplatePrizeLabels.length
          ? kResultTemplatePrizeLabels[i]
          : 'Prize ${i + 1}';
      buf.writeln('$label : ${_prizeValues[i]}');
    }
    final compliments = _complimentValues
        .where((c) => c.trim().isNotEmpty && c != '---')
        .map(resultTemplateFormatCompliment)
        .where((c) => c != '---')
        .toList();
    if (compliments.isNotEmpty) {
      buf.writeln('\nCompliments:\n${compliments.join(', ')}');
    }
    return buf.toString().trim();
  }

  Future<void> _shareResultScreenshot({bool hd = false}) async {
    final media = MediaQuery.of(context);
    final cardWidth = media.size.width;
    final cardHeight = media.size.height * 0.78;
    final captureCard = ResultShareCaptureCard(
      width: cardWidth,
      height: cardHeight,
      timeLabel: resultDrawCompactTime(_selectedDraw),
      dateLabel: resultDateFieldLabel(_resultDate),
      bookingWhatsappPhone: BookingContactStore.whatsappPhone.value,
      showBookingWhatsappBar: _showBookingWhatsappRow,
      prizes: List<String>.from(_prizeValues),
      compliments: List<String>.from(_complimentValues),
    );

    final pixelRatio = hd
        ? (media.devicePixelRatio < 3.0 ? 3.0 : media.devicePixelRatio)
        : media.devicePixelRatio;

    final image = await _shareCaptureController.captureFromLongWidget(
      MediaQuery(
        data: media.copyWith(textScaler: TextScaler.noScaling),
        child: captureCard,
      ),
      context: context,
      pixelRatio: pixelRatio,
      delay: const Duration(milliseconds: 800),
      constraints: BoxConstraints.tightFor(
        width: cardWidth,
        height: cardHeight,
      ),
    );
    if (image.isEmpty) {
      if (mounted) showErrorSnack(context, AppMsg.screenshotFailed);
      return;
    }
    await Share.shareXFiles(
      [
        XFile.fromData(
          image,
          mimeType: 'image/png',
          name: 'result_${_currentDrawCode()}_${_dateLine()}.png',
        ),
      ],
    );
  }

  Future<void> _shareResult() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(AppMsg.shareScreenshot),
              onTap: () => Navigator.pop(ctx, 'screenshot'),
            ),
            ListTile(
              leading: const Icon(Icons.message_outlined),
              title: Text(AppMsg.shareText),
              onTap: () => Navigator.pop(ctx, 'text'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      if (choice == 'screenshot') {
        await _shareResultScreenshot(hd: true);
        return;
      }

      final text = _buildShareText();
      if (text.isEmpty) {
        if (mounted) showErrorSnack(context, AppMsg.noResultToShare);
        return;
      }
      await Share.share(text);
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, AppMsg.shareFailed(e));
      }
    }
  }

  void _openEditResultPage() {
    Navigator.push(
      context,
      appRoute(
        EditDearResultPage(
          selectedDraw: _selectedDraw,
          resultDate: _resultDate,
          drawCode: _currentDrawCode(),
          initialPrizes: List<String>.from(_prizeValues),
          initialCompliments: List<String>.from(_complimentValues),
        ),
      ),
    ).then((saved) {
      if (saved == true && mounted) {
        _lastResultSignature = '';
        _loadSavedResult();
      }
    });
  }

  Future<void> _confirmDeleteResult() async {
    final code = _currentDrawCode();
    if (code.isEmpty) return;
    final existing = ResultStore.get(code, _resultDate);
    if (existing == null) {
      showErrorSnack(context, AppMsg.noResultToDelete);
      return;
    }

    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppMsg.deleteResultTitle),
        content: Text(
          AppMsg.deleteResultBody(
            _drawDisplayTitle(_selectedDraw),
            _dateLine(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppMsg.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppMsg.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    ResultStore.remove(code, _resultDate);
    _lastResultSignature = '';
    _clearResultUi();
    _stopCloudPoll();
    showSuccessSnack(context, AppMsg.resultDeleted);
  }

  @override
  void initState() {
    super.initState();
    _resultDate = calendarTodayInIndia();
    unawaited(_bootstrapResultView());
    ResultStore.results.addListener(_onResultStoreChanged);
    SyncService.restoring.addListener(_onRestoreChanged);
  }

  @override
  void dispose() {
    _stopCloudPoll();
    ResultStore.results.removeListener(_onResultStoreChanged);
    SyncService.restoring.removeListener(_onRestoreChanged);
    super.dispose();
  }

  void _onRestoreChanged() {
    if (!mounted) return;
    if (!SyncService.restoring.value) {
      _lastResultSignature = '';
      _loadSavedResult();
    }
    if (mounted) setState(() {});
  }


  Future<void> _shareViaWhatsApp() async {
    final hasPrizes = _prizeValues.any((v) => v.trim().isNotEmpty && v != '---');
    final hasCompliments = _complimentValues.any(
      (c) => c.trim().isNotEmpty && c != '---',
    );
    if (!hasPrizes && !hasCompliments) {
      if (mounted) showErrorSnack(context, AppMsg.noResultToShare);
      return;
    }
    try {
      await _shareResultScreenshot(hd: true);
    } catch (e) {
      if (mounted) showErrorSnack(context, AppMsg.shareFailed(e));
    }
  }

  Future<void> _pickDraw() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _draws
              .map(
                (d) => ListTile(
                  title: Text(d),
                  onTap: () => Navigator.pop(ctx, d),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDraw = picked);
    _onDrawOrDateChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bool loading = SyncService.restoring.value;
    return Stack(
      children: [
        Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kResultClassicHeaderBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: kResultClassicHeaderBlue,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Winning Numbers',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_canEditResult)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                switch (value) {
                  case 'manual':
                    _openEditResultPage();
                    break;
                  case 'delete':
                    _confirmDeleteResult();
                    break;
                  case 'live':
                    _openLiveYoutube();
                    break;
                  case 'share':
                    _shareResult();
                    break;
                  case 'booking_phone':
                    showBookingWhatsappPhoneEditor(context);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'manual',
                  child: Text(AppMsg.manualEntry),
                ),
                PopupMenuItem(
                  value: 'booking_phone',
                  child: const Text('Booking WhatsApp Phone'),
                ),
                if (ResultStore.get(_currentDrawCode(), _resultDate) != null)
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(AppMsg.deleteResultMenu),
                  ),
                PopupMenuItem(
                  value: 'live',
                  child: Text(AppMsg.liveStream),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Text(AppMsg.shareMenu),
                ),
              ],
            ),
        ],
      ),
      body: ResultPageTemplateBackground(
        child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: ResultWinningNumbersSearchRow(
                timeLabel: resultDrawCompactTime(_selectedDraw),
                dateLabel: resultDateFieldLabel(_resultDate),
                onTimeTap: _pickDraw,
                onDateTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _resultDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null && mounted) {
                    setState(() => _resultDate = picked);
                    _onDrawOrDateChanged();
                  }
                },
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: ResultWinningNumbersSearchButton(
                loading: _fetchingCloud,
                onPressed: () =>
                    _refreshCurrentDrawResult(userTriggered: true),
              ),
            ),
            const SizedBox(height: 10),
            if (_showBookingWhatsappRow) ...[
              ValueListenableBuilder<String>(
                valueListenable: BookingContactStore.whatsappPhone,
                builder: (context, phone, _) {
                  return ResultResultsTitleBar(
                    bookingWhatsappPhone: phone,
                  );
                },
              ),
              const SizedBox(height: 4),
            ],
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: LayoutBuilder(
                  builder: (context, inner) {
                    const double gapLabel = 4;
                    const double prizeFraction = 0.37;

                    final double avail = inner.maxHeight - gapLabel;
                    final double prizeH =
                        (avail * prizeFraction).clamp(0.0, double.infinity);
                    final double complimentsAreaH =
                        (avail - prizeH).clamp(0.0, double.infinity);
                    final double rowFontSize = complimentsAreaH > 0
                        ? (complimentsAreaH / 10 * 0.52).clamp(10.0, 14.0)
                        : 13.0;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: prizeH,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: List.generate(5, (i) {
                              return Expanded(
                                child: ResultTemplatePrizeBand(
                                  prizeIndex: i,
                                  value: _prizeValues[i],
                                  numberFontSize:
                                      kResultTemplatePrizeFontSizes[i],
                                ),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: gapLabel),
                        Expanded(
                          child: ResultTemplateComplimentsCard(
                            grid: buildResultTemplateComplimentsGrid(
                              fontSize: rowFontSize,
                              values: _complimentValues,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
              child: Center(
                child: Material(
                  color: const Color(0xFF25D366),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _shareViaWhatsApp,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: ResultWhatsappIcon(size: 28),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
        if (loading)
          Container(
            color: Colors.black26,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text(
                    'Restoring data...',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

List<String> _allowedDrawsForUser(String username) {
  final agent = UserStore.byUsername(username);
  if (agent == null || !agent.isAgentRole || agent.scheme == 'ALL') {
    return List<String>.from(kDrawTimeNames);
  }
  return kDrawTimeNames.where((d) => d == agent.scheme).toList();
}

bool _schemeAllowsDrawForUser(String username, String drawTime) {
  final allowed = _allowedDrawsForUser(username);
  return allowed.contains(drawTime.trim());
}

String _currentDrawForUser(String username, {DateTime? at}) {
  return DrawScheduleStore.currentDraw(
    at: at,
    allowed: _allowedDrawsForUser(username),
  );
}

String _menuDrawForUser(String username, {DateTime? at}) {
  return DrawScheduleStore.currentMenuDraw(
    at: at,
    allowed: _allowedDrawsForUser(username),
  );
}

Color _drawColorForName(String drawTime) => _drawColorForTime(drawTime);

void _openAddTicket(BuildContext context, String username, String draw) {
  if (UserStore.isSalesBlocked(username)) {
    showErrorSnack(context, AppMsg.salesBlocked);
    return;
  }
  if (!_schemeAllowsDrawForUser(username, draw)) {
    showErrorSnack(context, AppMsg.noDrawForScheme);
    return;
  }
  Navigator.push(
    context,
    appRoute(TicketPage(title: draw, username: username)),
  );
}

String _menuDrawResultTimeLabel(String drawTime) {
  if (drawTime.trim() == 'LSK 3 PM') return '3:07 PM';
  return DrawScheduleStore.drawResultTimeLabel(drawTime);
}

class _MenuDrawSelector extends StatefulWidget {
  final String username;
  final String selectedDraw;
  final DateTime now;
  final ValueChanged<String> onDrawChanged;

  const _MenuDrawSelector({
    required this.username,
    required this.selectedDraw,
    required this.now,
    required this.onDrawChanged,
  });

  @override
  State<_MenuDrawSelector> createState() => _MenuDrawSelectorState();
}

class _MenuDrawSelectorState extends State<_MenuDrawSelector> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final selectedDraw = widget.selectedDraw;
    final drawColor = menuDrawColor(selectedDraw);
    final close = DrawScheduleStore.drawCloseTimeLabel(selectedDraw);
    final drawAt = _menuDrawResultTimeLabel(selectedDraw);
    final open =
        DrawScheduleStore.isDrawBookingOpen(selectedDraw, at: widget.now);
    final countdown = DrawScheduleStore.bookingCloseCountdownText(
      selectedDraw,
      at: widget.now,
    );
    final allowed = _allowedDrawsForUser(widget.username);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.white, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: drawColor,
            child: InkWell(
              onTap: allowed.length > 1
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            menuDrawShortLabel(selectedDraw),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Close $close · Draw $drawAt',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                          if (open && countdown != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              'Closes in $countdown',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ] else if (!open) ...[
                            const SizedBox(height: 3),
                            Text(
                              AppMsg.bookingClosedStatus,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (allowed.length > 1)
                      Icon(
                        _expanded
                            ? Icons.arrow_drop_up
                            : Icons.arrow_drop_down,
                        color: Colors.white,
                        size: 30,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            ColoredBox(
              color: kAppBlue,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < allowed.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == allowed.length - 1 ? 0 : 8,
                        ),
                        child: Material(
                          color: menuDrawColor(allowed[i]),
                          child: InkWell(
                            onTap: () {
                              setState(() => _expanded = false);
                              widget.onDrawChanged(allowed[i]);
                            },
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Text(
                                menuDrawShortLabel(allowed[i]),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _bookingDrawPickerTile(
  BuildContext context, {
  required String name,
  required bool selected,
  required VoidCallback onTap,
}) {
  final color = _drawColorForName(name);
  final open = DrawScheduleStore.isDrawBookingOpen(name);
  final close = DrawScheduleStore.drawCloseTimeLabel(name);
  final drawAt = _menuDrawResultTimeLabel(name);
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? color
                        : (open
                            ? const Color(0xFF263238)
                            : Colors.grey.shade500),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Close $close · Draw $drawAt',
                  style: TextStyle(
                    fontSize: 11,
                    color: open ? Colors.grey.shade600 : Colors.red.shade400,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, size: 20, color: color)
          else
            Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
        ],
      ),
    ),
  );
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(pullBookingsFromCloud());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _reportPageBgDecoration(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _reportAppBar("Reports", context),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _simpleMenuCard([
                _simpleMenuTile(
                  context,
                  icon: Icons.calculate_outlined,
                  title: 'Sales Report',
                  onTap: () => Navigator.push(
                    context,
                    appRoute(const SalesReportPage()),
                  ),
                ),
                _simpleMenuTile(
                  context,
                  icon: Icons.emoji_events_outlined,
                  title: 'Winnings Report',
                  onTap: () => Navigator.push(
                    context,
                    appRoute(const WinningReportPage()),
                  ),
                ),
                _simpleMenuTile(
                  context,
                  icon: Icons.receipt_long_outlined,
                  title: 'Winning Bill Wise',
                  onTap: () => Navigator.push(
                    context,
                    appRoute(const WinningBillWiseSearchPage()),
                  ),
                ),
                _simpleMenuTile(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Net Pay',
                  onTap: () => Navigator.push(
                    context,
                    appRoute(const NetPayPage()),
                  ),
                ),
                _simpleMenuTile(
                  context,
                  icon: Icons.format_list_numbered_outlined,
                  title: 'Number Wise',
                  onTap: () => Navigator.push(
                    context,
                    appRoute(const NumberWiseReportPage()),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class WinningReportPage extends StatefulWidget {
  const WinningReportPage({super.key});

  @override
  State<WinningReportPage> createState() => _WinningReportPageState();
}

class _WinningReportPageState extends State<WinningReportPage> {
  String drawFilter = "ALL";
  String groupFilter = "Select";
  String userFilter = _defaultReportUserFilter();
  DateTime fromDate = defaultReportFromDate();
  DateTime toDate = defaultReportToDate();
  final TextEditingController ticketNumberController = TextEditingController();

  @override
  void dispose() {
    ticketNumberController.dispose();
    super.dispose();
  }

  bool _inRange(DateTime dt) {
    final DateTime d = DateTime(dt.year, dt.month, dt.day);
    final DateTime from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final DateTime to = DateTime(toDate.year, toDate.month, toDate.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  List<BillRecord> _filteredBills(List<BillRecord> bills) {
    final String ticketNo = ticketNumberController.text.trim();
    return bills.where((bill) {
      if (!_inRange(bill.businessDate)) return false;
      if (drawFilter != "ALL" &&
          !bill.rows.any((r) =>
              r["type"].toString().toUpperCase().startsWith(drawFilter))) {
        return false;
      }
      if (groupFilter != "Select" &&
          !bill.rows.any((r) =>
              r["type"].toString().toUpperCase().contains("-$groupFilter"))) {
        return false;
      }
      if (!_billMatchesReportUserFilter(bill, userFilter)) return false;
      if (ticketNo.isNotEmpty &&
          !bill.rows.any((r) => r["number"].toString().contains(ticketNo))) {
        return false;
      }
      final winningRows =
          _winningRowsForBill(bill, drawFilter: drawFilter);
      return winningRows.isNotEmpty;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(context: context, title: "Winning Report", body: ValueListenableBuilder<List<BillRecord>>(
        valueListenable: BillsStore.bills,
        builder: (context, bills, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _salesDrawBar(
                  selected: drawFilter,
                  onChanged: (v) => setState(() => drawFilter = v),
                  flat: true,
                ),
                const SizedBox(height: 10),
                _reportFormCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _reportDateBox(
                              context,
                              label: "From",
                              value: fromDate,
                              onChanged: (d) => setState(() => fromDate = d),
                              flat: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              "—",
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                          ),
                          Expanded(
                            child: _reportDateBox(
                              context,
                              label: "To",
                              value: toDate,
                              onChanged: (d) => setState(() => toDate = d),
                              flat: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: ticketNumberController,
                        keyboardType: TextInputType.number,
                        decoration:
                            _salesFieldDecoration("Ticket Number", flat: true),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: groupFilter,
                              decoration: _winningGroupDecoration(flat: true),
                              items: _winningGroupItems,
                              onChanged: (v) =>
                                  setState(() => groupFilter = v ?? "Select"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _reportUserFilterDropdown(
                              value: userFilter,
                              onChanged: (v) =>
                                  setState(() => userFilter = v),
                              flat: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _appGradientButton(
                        onPressed: () {
                          final filtered = _filteredBills(bills);
                          Navigator.push(
                            context,
                            appRoute(
                              WinningDetailsPage(
                                drawFilter: drawFilter,
                                filteredBills: filtered,
                              ),
                            ),
                          );
                        },
                        flat: true,
                        child: const Text("View Bills"),
                      ),
                    ],
                  ),
                  flat: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


class WinningDetailsPage extends StatelessWidget {
  final String drawFilter;
  final List<BillRecord> filteredBills;

  const WinningDetailsPage({
    super.key,
    required this.drawFilter,
    required this.filteredBills,
  });

  ({double win, double superAmt, double total}) _totals() =>
      _rangeWinningTotals(filteredBills, drawFilter: drawFilter);

  @override
  Widget build(BuildContext context) {
    final totals = _totals();
    final drawColor = _salesDrawColor(drawFilter);
    final allWinningRows = _allWinningRowsFromBills(
      filteredBills,
      drawFilter: drawFilter,
    );

    if (filteredBills.isEmpty) {
      return _reportPage(context: context, title: "Winning Details", body: const _WinningReportEmptyBody(),
      );
    }

    return _reportPage(context: context, title: "Winning Details", body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                _winningStatChip("Win", totals.win.toStringAsFixed(0), drawColor),
                const SizedBox(width: 8),
                _winningStatChip(
                    "Super", totals.superAmt.toStringAsFixed(0), drawColor),
                const SizedBox(width: 8),
                _winningStatChip(
                    "Total", totals.total.toStringAsFixed(0), drawColor),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (allWinningRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No winning lines for selected filters.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                else ...[
                  _winningDataColumnsHeader(),
                  ..._buildGroupedWinningRowWidgets(allWinningRows),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WinningBillWiseSearchPage extends StatefulWidget {
  const WinningBillWiseSearchPage({super.key});

  @override
  State<WinningBillWiseSearchPage> createState() =>
      _WinningBillWiseSearchPageState();
}

class _WinningBillWiseSearchPageState extends State<WinningBillWiseSearchPage> {
  String drawFilter = "ALL";
  String groupFilter = "Select";
  String modeFilter = "Select";
  DateTime selectedDate = defaultReportToDate();
  final TextEditingController ticketNumberController = TextEditingController();

  @override
  void dispose() {
    ticketNumberController.dispose();
    super.dispose();
  }

  bool _sameDate(DateTime a, DateTime b) => isSameBusinessDate(a, b);

  List<BillRecord> _filteredBills(List<BillRecord> bills) {
    final String ticketNo = ticketNumberController.text.trim();
    return bills.where((bill) {
      if (!_sameDate(bill.businessDate, selectedDate)) return false;
      if (drawFilter != "ALL" &&
          !bill.rows.any((r) =>
              r["type"].toString().toUpperCase().startsWith(drawFilter))) {
        return false;
      }
      if (groupFilter != "Select" &&
          !bill.rows.any((r) =>
              r["type"].toString().toUpperCase().contains("-$groupFilter"))) {
        return false;
      }
      if (modeFilter == "1" &&
          !bill.rows.any((r) => r["number"].toString().trim().length == 1)) {
        return false;
      }
      if (modeFilter == "2" &&
          !bill.rows.any((r) => r["number"].toString().trim().length == 2)) {
        return false;
      }
      if (modeFilter == "3" &&
          !bill.rows.any((r) => r["number"].toString().trim().length == 3)) {
        return false;
      }
      if (ticketNo.isNotEmpty &&
          !bill.rows.any((r) => r["number"].toString().contains(ticketNo))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(context: context, title: "Winning Bill Wise", body: ValueListenableBuilder<List<BillRecord>>(
        valueListenable: BillsStore.bills,
        builder: (context, bills, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _salesDrawBar(
                  selected: drawFilter,
                  onChanged: (v) => setState(() => drawFilter = v),
                ),
                const SizedBox(height: 10),
                _reportFormCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _reportDateBox(
                        context,
                        label: "Date",
                        value: selectedDate,
                        onChanged: (d) => setState(() => selectedDate = d),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: ticketNumberController,
                        keyboardType: TextInputType.number,
                        decoration:
                            _salesFieldDecoration("Ticket Number"),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: groupFilter,
                              decoration: _winningGroupDecoration(),
                              items: _winningGroupItems,
                              onChanged: (v) =>
                                  setState(() => groupFilter = v ?? "Select"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: modeFilter,
                              decoration: _winningModeDecoration(),
                              items: _winningModeItems,
                              onChanged: (v) =>
                                  setState(() => modeFilter = v ?? "Select"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _appGradientButton(
                        onPressed: () {
                          final filtered = _filteredBills(bills)
                              .where((b) => _winningRowsForBill(
                                    b,
                                    drawFilter: drawFilter,
                                  ).isNotEmpty)
                              .toList();
                          Navigator.push(
                            context,
                            appRoute(
                              WinningDetailsPage(
                                drawFilter: drawFilter,
                                filteredBills: filtered,
                              ),
                            ),
                          );
                        },
                        child: const Text("View Bills"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


class NetPayPage extends StatefulWidget {
  const NetPayPage({super.key});

  @override
  State<NetPayPage> createState() => _NetPayPageState();
}

class _NetPayPageState extends State<NetPayPage> {
  DateTime fromDate = defaultReportFromDate();
  DateTime toDate = defaultReportToDate();
  String drawFilter = "ALL";
  String groupFilter = "Select";
  String userFilter = _defaultReportUserFilter();

  List<BillRecord> _filteredBills(List<BillRecord> bills) {
    return bills.where((bill) {
      if (!billInDateRange(bill.businessDate, fromDate, toDate)) return false;
      if (drawFilter != "ALL" &&
          !bill.rows.any((r) => r["type"].toString().startsWith(drawFilter))) {
        return false;
      }
      if (groupFilter != "Select" &&
          !bill.rows.any((r) =>
              r["type"].toString().toUpperCase().contains("-$groupFilter"))) {
        return false;
      }
      if (!_billMatchesReportUserFilter(bill, userFilter)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: "Net Pay",
      body: ValueListenableBuilder<List<BillRecord>>(
        valueListenable: BillsStore.bills,
        builder: (context, bills, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _salesDrawBar(
                  selected: drawFilter,
                  onChanged: (v) => setState(() => drawFilter = v),
                  flat: true,
                ),
                const SizedBox(height: 10),
                _reportFormCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _reportDateBox(
                              context,
                              label: "From",
                              value: fromDate,
                              onChanged: (d) =>
                                  setState(() => fromDate = d),
                              flat: true,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              "—",
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                          ),
                          Expanded(
                            child: _reportDateBox(
                              context,
                              label: "To",
                              value: toDate,
                              onChanged: (d) => setState(() => toDate = d),
                              flat: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: groupFilter,
                              decoration: _winningGroupDecoration(flat: true),
                              items: _winningGroupItems,
                              onChanged: (v) =>
                                  setState(() => groupFilter = v ?? "Select"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _reportUserFilterDropdown(
                              value: userFilter,
                              onChanged: (v) =>
                                  setState(() => userFilter = v),
                              flat: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _appGradientButton(
                        onPressed: () {
                          final filtered = _filteredBills(bills);
                          Navigator.push(
                            context,
                            appRoute(
                              NetPayResultPage(
                                drawFilter: drawFilter,
                                filteredBills: filtered,
                                fromDate: fromDate,
                                toDate: toDate,
                              ),
                            ),
                          );
                        },
                        flat: true,
                        child: const Text("Generate Report"),
                      ),
                    ],
                  ),
                  flat: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NetPayResultPage extends StatelessWidget {
  final String drawFilter;
  final List<BillRecord> filteredBills;
  final DateTime fromDate;
  final DateTime toDate;

  const NetPayResultPage({
    super.key,
    required this.drawFilter,
    required this.filteredBills,
    required this.fromDate,
    required this.toDate,
  });

  ({double win, double superAmt, double total}) _billWinningBreakdown(
    BillRecord bill,
  ) {
    double win = 0;
    double superAmt = 0;
    for (final r in _winningRowsForBill(bill, drawFilter: drawFilter)) {
      win += BillRecord.winningWinFromRow(r);
      superAmt += BillRecord.winningSuperFromRow(r);
    }
    return (win: win, superAmt: superAmt, total: win + superAmt);
  }

  String _dateRangeText() {
    final f =
        "${fromDate.day.toString().padLeft(2, "0")}/${fromDate.month.toString().padLeft(2, "0")}/${fromDate.year}";
    final t =
        "${toDate.day.toString().padLeft(2, "0")}/${toDate.month.toString().padLeft(2, "0")}/${toDate.year}";
    return f == t ? f : "$f — $t";
  }

  Map<String, ({double sales, double win, double superAmt})> _userTotals() {
    final map = <String, ({double sales, double win, double superAmt})>{};
    for (final bill in filteredBills) {
      final user = bill.username.trim().isEmpty ? "Unknown" : bill.username;
      final prev = map[user] ?? (sales: 0.0, win: 0.0, superAmt: 0.0);
      final breakdown = _billWinningBreakdown(bill);
      map[user] = (
        sales: prev.sales + bill.totalAmount,
        win: prev.win + breakdown.win,
        superAmt: prev.superAmt + breakdown.superAmt,
      );
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final sales =
        filteredBills.fold<double>(0.0, (s, b) => s + b.totalAmount);
    final winTotals =
        _rangeWinningTotals(filteredBills, drawFilter: drawFilter);
    final winnings = winTotals.total;
    final nBalance = sales - winnings;
    final userTotals = _userTotals();
    final tint = _salesDrawTint(drawFilter);
    final sortedUsers = userTotals.keys.toList()..sort();

    return _reportPage(
      context: context,
      title: "Net Pay Result",
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: tint,
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateRangeText(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _salesDrawColor(drawFilter),
                      ),
                    ),
                  ),
                  Text(
                    _salesDrawLabel(drawFilter),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _salesDrawColor(drawFilter),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _netPayFlatHeaderRow(),
            _netPayFlatDataRow(
              user: 'TOTAL',
              sale: sales,
              win: winTotals.win,
              superAmt: winTotals.superAmt,
              totalWin: winnings,
              nBal: nBalance,
              bg: tint,
              bold: true,
            ),
            if (sortedUsers.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(color: Colors.grey.shade300),
                    right: BorderSide(color: Colors.grey.shade300),
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Text(
                  'No bills in selected range',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              )
            else
              ...sortedUsers.asMap().entries.map((entry) {
                final i = entry.key;
                final user = entry.value;
                final totals = userTotals[user]!;
                final totalWin = totals.win + totals.superAmt;
                final nBal = totals.sales - totalWin;
                final rowBg = drawFilter != 'ALL'
                    ? _salesDrawTint(drawFilter)
                    : _kWinningPrizeLiteColors[
                        i % _kWinningPrizeLiteColors.length];
                return _netPayFlatDataRow(
                  user: user,
                  sale: totals.sales,
                  win: totals.win,
                  superAmt: totals.superAmt,
                  totalWin: totalWin,
                  nBal: nBal,
                  bg: rowBg,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _netPayFlatHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: kAppBlue,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          _netPayFlatCell('User', flex: 3, header: true, align: TextAlign.left),
          _netPayFlatCell('Sale', header: true),
          _netPayFlatCell('Win', header: true),
          _netPayFlatCell('Super', header: true),
          _netPayFlatCell('Tot Win', header: true),
          _netPayFlatCell('N.Bal', header: true),
        ],
      ),
    );
  }

  Widget _netPayFlatDataRow({
    required String user,
    required double sale,
    required double win,
    required double superAmt,
    required double totalWin,
    required double nBal,
    Color? bg,
    bool bold = false,
  }) {
    const winTint = Color(0xFFFFEBEE);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        border: Border(
          left: BorderSide(color: Colors.grey.shade300),
          right: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: [
          _netPayFlatCell(
            user,
            flex: 3,
            bold: bold,
            align: TextAlign.left,
          ),
          _netPayFlatCell(sale.toStringAsFixed(0), bold: bold),
          _netPayFlatCell(
            win.toStringAsFixed(0),
            bold: bold,
            bg: winTint,
            textColor: const Color(0xFFC62828),
          ),
          _netPayFlatCell(
            superAmt.toStringAsFixed(0),
            bold: bold,
            bg: winTint,
            textColor: const Color(0xFFC62828),
          ),
          _netPayFlatCell(
            totalWin.toStringAsFixed(0),
            bold: bold,
            bg: winTint,
            textColor: const Color(0xFFB71C1C),
          ),
          _netPayFlatCell(
            nBal.toStringAsFixed(0),
            bold: bold,
            bg: const Color(0xFFE3F2FD),
            textColor: _appPrimary,
          ),
        ],
      ),
    );
  }

  Widget _netPayFlatCell(
    String text, {
    int flex = 2,
    bool header = false,
    bool bold = false,
    TextAlign align = TextAlign.right,
    Color? color,
    Color? textColor,
    Color? bg,
  }) {
    return Expanded(
      flex: flex,
      child: Container(
        color: bg,
        padding: bg != null
            ? const EdgeInsets.symmetric(vertical: 2, horizontal: 2)
            : EdgeInsets.zero,
        child: Text(
          text,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: header ? 12 : 13,
            fontWeight: header || bold ? FontWeight.w700 : FontWeight.w500,
            color: header
                ? Colors.white
                : (textColor ?? color ?? const Color(0xFF263238)),
          ),
        ),
      ),
    );
  }
}

class NumberWiseReportPage extends StatefulWidget {
  const NumberWiseReportPage({super.key});

  @override
  State<NumberWiseReportPage> createState() => _NumberWiseReportPageState();
}

class _NumberWiseReportPageState extends State<NumberWiseReportPage> {
  String drawFilter = "ALL";
  String groupFilter = "Select";
  String modeFilter = "Select";
  bool groupWithoutTicketName = false;
  DateTime selectedDate = defaultReportToDate();
  final TextEditingController ticketNumberController = TextEditingController();

  @override
  void dispose() {
    ticketNumberController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _buildRows(List<BillRecord> bills) {
    final String ticketNo = ticketNumberController.text.trim();
    final Map<String, int> totals = {};

    for (final bill in bills) {
      if (!billInDateRange(bill.businessDate, selectedDate, selectedDate)) {
        continue;
      }
      for (final row in bill.rows) {
        final String type = row["type"].toString().toUpperCase();
        final String number = row["number"].toString();
        final int count = int.tryParse(row["count"].toString()) ?? 0;
        if (count <= 0) continue;

        if (drawFilter != "ALL" && !type.startsWith(drawFilter)) continue;
        if (groupFilter != "Select" && !type.contains("-$groupFilter")) {
          continue;
        }
        if (modeFilter != "Select" &&
            number.length != (int.tryParse(modeFilter) ?? 0)) {
          continue;
        }
        if (ticketNo.isNotEmpty && !number.contains(ticketNo)) continue;

        final String ticketKey = groupWithoutTicketName
            ? type.split("-").last
            : type.replaceFirst("DEAR", "DEAR-");
        final String key = "$ticketKey|$number";
        totals[key] = (totals[key] ?? 0) + count;
      }
    }

    return totals.entries.map((e) {
      final parts = e.key.split("|");
      return {
        "ticket": parts.first,
        "number": parts.length > 1 ? parts[1] : "",
        "count": e.value,
      };
    }).toList()
      ..sort((a, b) => (b["count"] as int).compareTo(a["count"] as int));
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: "Number Wise Report",
      body: ValueListenableBuilder<List<BillRecord>>(
        valueListenable: BillsStore.bills,
        builder: (context, bills, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _salesDrawBar(
                  selected: drawFilter,
                  onChanged: (v) => setState(() => drawFilter = v),
                ),
                const SizedBox(height: 10),
                _reportFormCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _reportDateBox(
                        context,
                        label: "Date",
                        value: selectedDate,
                        onChanged: (d) => setState(() => selectedDate = d),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: ticketNumberController,
                        keyboardType: TextInputType.number,
                        decoration:
                            _salesFieldDecoration("Ticket Number"),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: groupFilter,
                              decoration: _winningGroupDecoration(),
                              items: _winningGroupItems,
                              onChanged: (v) =>
                                  setState(() => groupFilter = v ?? "Select"),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: modeFilter,
                              decoration: _winningModeDecoration(),
                              items: _winningModeItems,
                              onChanged: (v) =>
                                  setState(() => modeFilter = v ?? "Select"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.zero,
                          onTap: () => setState(
                              () => groupWithoutTicketName =
                                  !groupWithoutTicketName),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: groupWithoutTicketName,
                                  activeColor: _appGradient.first,
                                  onChanged: (v) => setState(() =>
                                      groupWithoutTicketName = v ?? false),
                                ),
                                const Expanded(
                                  child: Text(
                                    "Group without ticket name",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _appGradientButton(
                        onPressed: () {
                          final rows = _buildRows(bills);
                          Navigator.push(
                            context,
                            appRoute(
                              NumberWiseResultPage(
                                rows: rows,
                                drawFilter: drawFilter,
                                selectedDate: selectedDate,
                              ),
                            ),
                          );
                        },
                        child: const Text("Generate Report"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class NumberWiseResultPage extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String drawFilter;
  final DateTime selectedDate;

  const NumberWiseResultPage({
    super.key,
    required this.rows,
    required this.drawFilter,
    required this.selectedDate,
  });

  String _drawFromTicket(String ticket) {
    final t = ticket.toUpperCase();
    if (t.startsWith("DEAR1") || t.contains("DEAR-1")) return "DEAR1";
    if (t.startsWith("LSK3")) return "LSK3";
    if (t.startsWith("DEAR6") || t.contains("DEAR-6")) return "DEAR6";
    if (t.startsWith("DEAR8") || t.contains("DEAR-8")) return "DEAR8";
    return drawFilter == "ALL" ? "ALL" : drawFilter;
  }

  String _dateText() =>
      "${selectedDate.day.toString().padLeft(2, "0")}/${selectedDate.month.toString().padLeft(2, "0")}/${selectedDate.year}";

  @override
  Widget build(BuildContext context) {
    final int total =
        rows.fold<int>(0, (s, r) => s + ((r["count"] as int?) ?? 0));
    final tint = _salesDrawTint(drawFilter);

    if (rows.isEmpty) {
      return _reportPage(
        context: context,
        title: "Number Wise Result",
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.numbers_outlined,
                    size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  "No numbers found",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dateText(),
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return _reportPage(
      context: context,
      title: "Number Wise Result",
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dateText(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _salesDrawColor(drawFilter),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: Text(
                          _salesDrawLabel(drawFilter),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _salesDrawColor(drawFilter),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      _salesStatChip(
                        "Numbers",
                        "${rows.length}",
                        tint,
                      ),
                      const SizedBox(width: 8),
                      _salesStatChip(
                        "Total Qty",
                        "$total",
                        _appGradient.first.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                final ticket = row["ticket"].toString();
                final number = row["number"].toString();
                final count = (row["count"] as int?) ?? 0;
                final code = _drawFromTicket(ticket);
                final color = _salesDrawColor(code);
                final bg = color.withValues(alpha: 0.07);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Text(
                            "${i + 1}",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ticket,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                number,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Text(
                            "$count",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(color: kAppBlue),
            child: SafeArea(
              top: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Quantity",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      "$total",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SalesReportPage extends StatefulWidget {
  const SalesReportPage({super.key});
  @override
  State<SalesReportPage> createState() => _SalesReportPageState();
}

class _SalesReportPageState extends State<SalesReportPage> {
  final TextEditingController ticketNumberController = TextEditingController();
  String drawFilter = "ALL";
  String groupFilter = "Select";
  String userFilter = _defaultReportUserFilter();
  DateTime fromDate = defaultSalesReportDate();
  DateTime toDate = defaultSalesReportDate();

  @override
  void initState() {
    super.initState();
    fromDate = defaultSalesReportDate();
    toDate = defaultSalesReportDate();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await pullBookingsFromCloud();
      if (!mounted) return;
      setState(() {
        fromDate = defaultSalesReportDate();
        toDate = defaultSalesReportDate();
      });
    });
  }

  @override
  void dispose() {
    ticketNumberController.dispose();
    super.dispose();
  }

  String _timeText(DateTime dt) => formatBillDateTime(dt);

  List<BillRecord> _filteredBills(List<BillRecord> bills) {
    final String ticketNo = ticketNumberController.text.trim();
    return bills.where((bill) {
      if (!billInDateRange(bill.businessDate, fromDate, toDate)) return false;
      if (!_billMatchesReportUserFilter(bill, userFilter)) return false;
      bool ok = true;
      if (drawFilter != "ALL") {
        ok = ok &&
            bill.rows.any((r) => r["type"].toString().startsWith(drawFilter));
      }
      if (groupFilter != "Select") {
        final int? digitMode = int.tryParse(groupFilter);
        if (digitMode != null) {
          ok = ok &&
              bill.rows.any(
                  (r) => r["number"].toString().trim().length == digitMode);
        }
      }
      if (ticketNo.isNotEmpty) {
        ok = ok &&
            bill.rows.any((r) => r["number"].toString().contains(ticketNo));
      }
      return ok;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(context: context, title: "Sales Report", body: ValueListenableBuilder<List<BillRecord>>(
        valueListenable: BillsStore.bills,
        builder: (context, bills, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _salesDrawBar(
                  selected: drawFilter,
                  onChanged: (v) => setState(() => drawFilter = v),
                  flat: true,
                ),
                const SizedBox(height: 10),
                _reportFormCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: _dateBox("From", fromDate,
                                  (d) => setState(() => fromDate = d))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              "—",
                              style: TextStyle(color: Colors.grey.shade400),
                            ),
                          ),
                          Expanded(
                              child: _dateBox("To", toDate,
                                  (d) => setState(() => toDate = d))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: ticketNumberController,
                        decoration:
                            _salesFieldDecoration("Ticket Number", flat: true),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _groupDropdown()),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _reportUserFilterDropdown(
                              value: userFilter,
                              onChanged: (v) =>
                                  setState(() => userFilter = v),
                              flat: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _appGradientButton(
                        onPressed: () {
                          final filtered = _filteredBills(bills)
                              .map((b) => BillsStore.byBillNo(b.billNo) ?? b)
                              .toList();
                          Navigator.push(
                            context,
                            appRoute(
                              SalesReportDetailedPage(
                                filteredBills: filtered,
                                drawFilter: drawFilter,
                                timeTextBuilder: _timeText,
                              ),
                            ),
                          );
                        },
                        flat: true,
                        child: const Text("View Bills"),
                      ),
                    ],
                  ),
                  flat: true,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _groupDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: groupFilter,
      decoration: _salesFieldDecoration("Digits", flat: true),
      items: const [
        DropdownMenuItem(value: "Select", child: Text("All")),
        DropdownMenuItem(value: "3", child: Text("3 digit")),
        DropdownMenuItem(value: "2", child: Text("2 digit")),
        DropdownMenuItem(value: "1", child: Text("1 digit")),
      ],
      onChanged: (v) => setState(() => groupFilter = v ?? "Select"),
    );
  }

  Widget _dateBox(
      String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(_calendarDate(picked));
      },
      child: InputDecorator(
        decoration: _salesFieldDecoration(label, flat: true),
        child: Text(
          "${value.day.toString().padLeft(2, "0")}/${value.month.toString().padLeft(2, "0")}/${value.year}",
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }
}

/// Shown when there are no saved bills matching the report (all sales report screens).
class _SalesReportEmptyBody extends StatelessWidget {
  const _SalesReportEmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              "No sales data",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class SalesReportDetailedPage extends StatefulWidget {
  final List<BillRecord> filteredBills;
  final String drawFilter;
  final String Function(DateTime dt) timeTextBuilder;

  const SalesReportDetailedPage({
    super.key,
    required this.filteredBills,
    required this.drawFilter,
    required this.timeTextBuilder,
  });

  @override
  State<SalesReportDetailedPage> createState() =>
      _SalesReportDetailedPageState();
}

class _SalesReportDetailedPageState extends State<SalesReportDetailedPage> {
  late List<BillRecord> _bills;
  final Set<int> _expandedBillNos = {};
  bool _expandAll = false;

  static const Color _rcData = Color(0xFF212121);

  @override
  void initState() {
    super.initState();
    _bills = widget.filteredBills
        .map((b) => BillsStore.byBillNo(b.billNo) ?? b)
        .toList();
  }

  List<BillRecord> get _visibleBills =>
      _bills.where((b) => _billRowsForFilter(b).isNotEmpty).toList();

  List<Map<String, dynamic>> _billRowsForFilter(BillRecord bill) {
    final out = <Map<String, dynamic>>[];
    for (final row in bill.rows) {
      if (!_salesRowMatchesDraw(row, widget.drawFilter)) continue;
      final count = int.tryParse(row['count'].toString()) ?? 0;
      if (count <= 0) continue;
      out.add(row);
    }
    return out;
  }

  void _toggleExpandAll() {
    setState(() {
      _expandAll = !_expandAll;
      if (_expandAll) {
        _expandedBillNos
          ..clear()
          ..addAll(_visibleBills.map((b) => b.billNo));
      } else {
        _expandedBillNos.clear();
      }
    });
  }

  void _toggleBill(int billNo) {
    setState(() {
      if (_expandedBillNos.contains(billNo)) {
        _expandedBillNos.remove(billNo);
        _expandAll = false;
      } else {
        _expandedBillNos.add(billNo);
        _expandAll = _expandedBillNos.length == _visibleBills.length;
      }
    });
  }

  String _billDateShort(DateTime dt) {
    final local = dt.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}-'
        '${(local.year % 100).toString().padLeft(2, '0')}';
  }

  String _billTime24(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDeleteBill(BillRecord bill) async {
    final now = DateTime.now();
    if (!bill.isModifiable(at: now)) {
      final msg = bill.modifyBlockMessage(at: now);
      if (msg != null) showErrorSnack(context, msg);
      return;
    }

    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppMsg.deleteBillTitle),
        content: Text(
          AppMsg.deleteBillBody(bill.billNo),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppMsg.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppMsg.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    BillsStore.delete(bill.billNo);
    setState(() {
      _bills.removeWhere((b) => b.billNo == bill.billNo);
      _expandedBillNos.remove(bill.billNo);
      if (_expandedBillNos.length != _visibleBills.length) {
        _expandAll = false;
      }
    });
    if (_bills.isEmpty && mounted) {
      Navigator.pop(context);
      return;
    }
    showSuccessSnack(context, AppMsg.billDeleted(bill.billNo));
  }

  Future<void> _openReceiptEditPage(BillRecord bill) async {
    final bool? deleted = await Navigator.push<bool>(
      context,
      appRoute(EditBillPage(initialBillNo: bill.billNo)),
    );
    if (!mounted) return;

    setState(() {
      if (deleted == true) {
        _bills.removeWhere((b) => b.billNo == bill.billNo);
        _expandedBillNos.remove(bill.billNo);
      } else {
        final updated = BillsStore.byBillNo(bill.billNo);
        if (updated == null) {
          _bills.removeWhere((b) => b.billNo == bill.billNo);
          _expandedBillNos.remove(bill.billNo);
        } else {
          final idx = _bills.indexWhere((b) => b.billNo == bill.billNo);
          if (idx >= 0) _bills[idx] = updated;
        }
      }
      if (_expandedBillNos.length != _visibleBills.length) {
        _expandAll = false;
      }
    });

    if (_bills.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  String _salesDrawFooterLabel(String code) {
    switch (code.toUpperCase()) {
      case 'DEAR1':
        return menuDrawShortLabel('DEAR 1 PM');
      case 'LSK3':
        return menuDrawShortLabel('LSK 3 PM');
      case 'DEAR6':
        return menuDrawShortLabel('DEAR 6 PM');
      case 'DEAR8':
        return menuDrawShortLabel('DEAR 8 PM');
      default:
        return _salesDrawLabel(code);
    }
  }

  Color _salesDetailRowColor(String type) {
    final code = widget.drawFilter != 'ALL'
        ? widget.drawFilter
        : _drawCodeFromRowType(type);
    return _salesDrawColor(code);
  }

  Widget _salesReportFooter({
    required int count,
    required double amount,
  }) {
    final drawCode = widget.drawFilter;
    final drawColor = drawCode != 'ALL'
        ? _salesDrawColor(drawCode)
        : kAppBlueLight;
    final drawLabel =
        drawCode != 'ALL' ? _salesDrawFooterLabel(drawCode) : null;

    Widget totalCell(String label, String value) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _rcData,
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (drawLabel != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: drawColor,
              child: Text(
                drawLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: drawColor.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                totalCell('COUNT', count.toStringAsFixed(2)),
                totalCell('AMOUNT', formatSalesAmount(amount)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesExpandedLineRow(Map<String, dynamic> row) {
    final type = row['type'].toString();
    final count = row['count'].toString();
    final amount = BillRecord.readRowAmount(row['amount']);
    final rowColor = _salesDetailRowColor(type);
    const lineStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.28),
            width: 0.5,
          ),
          left: BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.5,
          ),
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              _salesRowTypeDisplayLabel(type),
              style: lineStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row['number'].toString(),
              textAlign: TextAlign.center,
              style: lineStyle,
            ),
          ),
          Expanded(
            child: Text(
              count,
              textAlign: TextAlign.center,
              style: lineStyle,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              amount.toStringAsFixed(2),
              textAlign: TextAlign.end,
              style: lineStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesBillCard(BillRecord bill) {
    final displayBill = BillsStore.byBillNo(bill.billNo) ?? bill;
    final expanded = _expandedBillNos.contains(displayBill.billNo);
    final rows = _billRowsForFilter(displayBill);
    final totals = _salesBillDetailsTotals(
      [displayBill],
      drawFilter: widget.drawFilter,
    );
    const summaryStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: kAppBlue,
    );
    final billName = displayBill.billNote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          child: InkWell(
            onTap: () => _toggleBill(displayBill.billNo),
            onLongPress: () => _openReceiptEditPage(displayBill),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${displayBill.billNo}', style: summaryStyle),
                            if (billName.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                billName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: summaryStyle.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: kAppBlueDark,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          _billTime24(displayBill.createdAt),
                          textAlign: TextAlign.center,
                          style: summaryStyle,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${totals.count}',
                          textAlign: TextAlign.center,
                          style: summaryStyle,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          formatSalesAmount(totals.agent),
                          textAlign: TextAlign.end,
                          style: summaryStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _billDateShort(displayBill.businessDate),
                          style: summaryStyle.copyWith(fontSize: 15),
                        ),
                      ),
                      Material(
                        color: Colors.grey.shade500,
                        borderRadius: BorderRadius.zero,
                        child: InkWell(
                          onTap: () => _confirmDeleteBill(displayBill),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            child: Text(
                              'Delete Bill',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Column(
            children: rows.asMap().entries.map(
                  (e) => _salesExpandedLineRow(e.value),
                ).toList(),
          ),
        Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = _salesBillDetailsTotals(
      _bills,
      drawFilter: widget.drawFilter,
    );
    final visibleBills = _visibleBills;

    return Scaffold(
      body: Container(
        decoration: _reportPageBgDecoration(),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: _reportAppBar(
            'Sales Report',
            context,
            extraActions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: OutlinedButton(
                  onPressed:
                      visibleBills.isEmpty ? null : _toggleExpandAll,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _expandAll ? 'COLLAPSE ALL' : 'EXPAND ALL',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: visibleBills.isEmpty
              ? const _SalesReportEmptyBody()
              : ListView.builder(
                  itemCount: visibleBills.length,
                  itemBuilder: (context, index) =>
                      _salesBillCard(visibleBills[index]),
                ),
          bottomNavigationBar: visibleBills.isEmpty
              ? null
              : _salesReportFooter(
                  count: totals.count,
                  amount: totals.agent,
                ),
        ),
      ),
    );
  }
}

class EditBillPage extends StatefulWidget {
  final int? initialBillNo;
  const EditBillPage({super.key, this.initialBillNo});

  @override
  State<EditBillPage> createState() => _EditBillPageState();
}

class _EditBillPageState extends State<EditBillPage> {
  late final TextEditingController billNoController;
  BillRecord? selectedBill;
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  bool get _directEdit => widget.initialBillNo != null;

  bool get _canModifyBill =>
      selectedBill?.isModifiable(at: _now) ?? false;

  void _showBillModifyBlockedMessage() {
    final bill = selectedBill;
    if (bill == null || !mounted) return;
    final msg = bill.modifyBlockMessage(at: _now);
    if (msg == null) return;
    showErrorSnack(context, msg);
  }

  @override
  void initState() {
    super.initState();
    billNoController = TextEditingController(
      text: widget.initialBillNo?.toString() ?? "",
    );
    selectedBill = widget.initialBillNo == null
        ? null
        : BillsStore.byBillNo(widget.initialBillNo!);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    billNoController.dispose();
    super.dispose();
  }

  void _search() {
    final int? billNo = int.tryParse(billNoController.text.trim());
    if (billNo == null) {
      showErrorSnack(context, AppMsg.enterValidBillNo);
      return;
    }
    final BillRecord? bill = BillsStore.byBillNo(billNo);
    setState(() => selectedBill = bill);
    if (bill == null) {
      showErrorSnack(context, AppMsg.billNotFound(billNo));
    }
  }

  Future<void> _deleteBill() async {
    final int? billNo = int.tryParse(billNoController.text.trim());
    if (billNo == null) {
      showErrorSnack(context, AppMsg.enterValidBillNo);
      return;
    }
    final BillRecord? bill = BillsStore.byBillNo(billNo);
    if (bill == null) {
      showErrorSnack(context, AppMsg.billNotFound(billNo));
      return;
    }
    if (!bill.isModifiable(at: _now)) {
      final msg = bill.modifyBlockMessage(at: _now);
      if (msg != null) showErrorSnack(context, msg);
      return;
    }

    final bool? ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppMsg.deleteReceiptTitle),
        content: Text(
          AppMsg.deleteReceiptBody(billNo),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppMsg.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppMsg.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    BillsStore.delete(billNo);
    if (_directEdit) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => selectedBill = null);
    showSuccessSnack(context, AppMsg.billDeleted(billNo));
  }

  void _deleteRow(int index) {
    if (selectedBill == null) return;
    if (!_canModifyBill) {
      _showBillModifyBlockedMessage();
      return;
    }
    setState(() => selectedBill!.rows.removeAt(index));
    BillsStore.notifyUpdated(selectedBill);
    if (selectedBill!.rows.isEmpty) {
      showSuccessSnack(
        context,
        AppMsg.allLinesRemoved,
      );
    }
  }

  Future<void> _showBillRowOptions(int index) async {
    if (selectedBill == null) return;
    if (!_canModifyBill) {
      _showBillModifyBlockedMessage();
      return;
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(AppMsg.editNumber),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade600),
              title: Text(
                AppMsg.deleteLine,
                style: TextStyle(color: Colors.red.shade600),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _editRow(index);
    } else if (action == 'delete') {
      _deleteRow(index);
    }
  }

  Future<void> _editRow(int index) async {
    if (selectedBill == null) return;
    if (!_canModifyBill) {
      _showBillModifyBlockedMessage();
      return;
    }
    final row = selectedBill!.rows[index];
    final numberEditController =
        TextEditingController(text: row["number"].toString());
    final countEditController =
        TextEditingController(text: row["count"].toString());

    final bool? ok = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppMsg.editRowTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numberEditController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: AppMsg.numberLabel),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: countEditController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: AppMsg.countLabel),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppMsg.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppMsg.save)),
        ],
      ),
    );
    if (ok != true) return;

    final String updatedNumber = numberEditController.text.trim();
    final int updatedCount = int.tryParse(countEditController.text.trim()) ?? 0;
    if (updatedNumber.isEmpty || updatedCount <= 0) return;

    final int oldCount = int.tryParse(row["count"].toString()) ?? 1;
    final double unitRate = row.containsKey('rate')
        ? BillRecord.readRowRate(row['rate'])
        : (oldCount > 0
            ? BillRecord.readRowAmount(row["amount"]) / oldCount
            : 0.0);

    setState(() {
      row["number"] = updatedNumber;
      row["count"] = updatedCount.toString();
      row["rate"] = unitRate;
      row["amount"] = unitRate * updatedCount;
    });
    BillsStore.notifyUpdated(selectedBill);
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return "${local.year.toString().padLeft(4, "0")}-"
        "${local.month.toString().padLeft(2, "0")}-"
        "${local.day.toString().padLeft(2, "0")}";
  }

  String _formatTime(DateTime dt) {
    final int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final String ampm = dt.hour >= 12 ? "PM" : "AM";
    return "${dt.month}/${dt.day}, $hour12:${dt.minute.toString().padLeft(2, "0")} $ampm";
  }

  Color _gameColorFromBill(BillRecord? bill) {
    if (bill == null || bill.rows.isEmpty) return Colors.blue;
    final String type = bill.rows.first["type"].toString().toUpperCase();
    if (type.startsWith("DEAR1")) return kDraw1PmColor;
    if (type.startsWith("DEAR6")) return kDraw6PmColor;
    if (type.startsWith("DEAR8")) return kDraw8PmColor;
    if (type.startsWith("LSK3")) return kDraw3PmColor;
    return Colors.blue;
  }

  String _gameNameFromBill(BillRecord? bill) {
    if (bill == null || bill.rows.isEmpty) return "-";
    return bill.drawTimeName;
  }

  String _formatSaleTime(DateTime dt) {
    final local = dt.toLocal();
    return "${local.hour.toString().padLeft(2, "0")}:"
        "${local.minute.toString().padLeft(2, "0")}:"
        "${local.second.toString().padLeft(2, "0")}";
  }

  String _billDrawShort(String drawName) {
    switch (drawName.trim()) {
      case 'DEAR 1 PM':
        return '1PM';
      case 'LSK 3 PM':
        return '3PM';
      case 'DEAR 6 PM':
        return '6PM';
      case 'DEAR 8 PM':
        return '8PM';
      default:
        return drawName.replaceAll(' ', '');
    }
  }

  String _billTicketLabel(String type, String drawName) {
    final i = type.lastIndexOf('-');
    final suffix = i >= 0 ? type.substring(i + 1).toUpperCase() : type.toUpperCase();
    final drawShort = _billDrawShort(drawName);
    switch (suffix) {
      case 'SUPER':
        return 'Super-$drawShort';
      case 'BOX':
        return 'Box-$drawShort';
      case 'A':
        return 'A-$drawShort';
      case 'B':
        return 'B-$drawShort';
      case 'C':
        return 'C-$drawShort';
      case 'AB':
        return 'AB-$drawShort';
      case 'BC':
        return 'BC-$drawShort';
      case 'AC':
        return 'AC-$drawShort';
      default:
        return type;
    }
  }

  String _formatBillFooterAmount(double value) {
    if ((value - value.roundToDouble()).abs() < 0.001) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  Widget _billMetaLabelValue(String label, String value,
      {TextAlign align = TextAlign.start}) {
    return RichText(
      textAlign: align,
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: Color(0xFF212121)),
        children: [
          TextSpan(text: '$label : '),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  String _billDrawDisplayName(String draw) => menuDrawShortLabel(draw);

  Color _billRowDrawColor(BillRecord bill, String rowType) {
    final code = _drawCodeFromRowType(rowType);
    if (code != 'ALL') return _salesDrawColor(code);
    final fromDraw = _drawCodeFromFilter(bill.effectiveDrawName);
    if (fromDraw.isNotEmpty) return _salesDrawColor(fromDraw);
    return _drawColorForTime(bill.effectiveDrawName);
  }

  Color _billFooterDrawColor(BillRecord bill) {
    final fromDraw = _drawCodeFromFilter(bill.effectiveDrawName);
    if (fromDraw.isNotEmpty) return _salesDrawColor(fromDraw);
    if (bill.rows.isNotEmpty) {
      return _billRowDrawColor(bill, bill.rows.first['type'].toString());
    }
    return kAppBlue;
  }

  Widget _buildBillDetailsView(BillRecord bill) {
    const tableHeader = Color(0xFF616161);
    final billNote = bill.billNote;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: kAppBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Bill Details',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        actions: [
          if (_canModifyBill)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteBill,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (bill.modifyBlockMessage(at: _now) != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: Colors.red.shade50,
                      child: Text(
                        bill.modifyBlockMessage(at: _now)!,
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _billMetaLabelValue(
                            'Bil NO',
                            bill.billNo.toString(),
                          ),
                        ),
                        Expanded(
                          child: _billMetaLabelValue(
                            'Draw Date',
                            _formatDate(bill.businessDate),
                            align: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _billMetaLabelValue(
                            'Draw',
                            _billDrawDisplayName(bill.effectiveDrawName),
                          ),
                        ),
                        Expanded(
                          child: _billMetaLabelValue(
                            'Sale Time',
                            _formatSaleTime(bill.createdAt),
                            align: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: _billMetaLabelValue('A', bill.username),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _billMetaLabelValue(
                              'Bill Note',
                              billNote.isNotEmpty ? billNote : '',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade300),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: _billMetaLabelValue('SA', bill.username),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Column(
                      children: [
                        Container(
                          color: tableHeader,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: const Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  'Ticket',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Number',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Count',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Amount',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...bill.rows.asMap().entries.map((entry) {
                          final index = entry.key;
                          final row = entry.value;
                          final amount =
                              BillRecord.readRowAmount(row['amount']);
                          final rowColor = _billRowDrawColor(
                            bill,
                            row['type'].toString(),
                          );
                          const rowTextStyle = TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          );
                          return Material(
                            color: rowColor,
                            child: InkWell(
                              onLongPress: () => _showBillRowOptions(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.28),
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        _billTicketLabel(
                                          row['type'].toString(),
                                          bill.effectiveDrawName,
                                        ),
                                        style: rowTextStyle,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        row['number'].toString(),
                                        textAlign: TextAlign.center,
                                        style: rowTextStyle,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        row['count'].toString(),
                                        textAlign: TextAlign.center,
                                        style: rowTextStyle,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        amount.toStringAsFixed(2),
                                        textAlign: TextAlign.center,
                                        style: rowTextStyle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _billFooterDrawColor(bill),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.28),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'COUNT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            bill.totalCount.toString(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'AMOUNT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatBillFooterAmount(bill.totalAmount),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = selectedBill;

    if (_directEdit) {
      if (bill == null) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bill Details'),
          ),
          body: Center(child: Text(AppMsg.billNotFoundShort)),
        );
      }
      return _buildBillDetailsView(bill);
    }

    final themeColor = _gameColorFromBill(bill);
    final gameName = _gameNameFromBill(bill);
    final modifyBlockMsg = bill?.modifyBlockMessage(at: _now);

    return _reportPage(
      context: context,
      title: _directEdit ? 'Edit Receipt' : 'Edit / Delete',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (!_directEdit)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: billNoController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Bill number',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _search,
                          child: const Text('Search'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _deleteBill,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade200),
                          ),
                          child: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (bill != null) ...[
            if (!_directEdit) const SizedBox(height: 12),
            if (modifyBlockMsg != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  modifyBlockMsg,
                  style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bill ${bill.billNo}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$gameName · ${bill.username}',
                    style: TextStyle(
                      color: themeColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDate(bill.businessDate)} · ${_formatTime(bill.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (bill.billNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Bill Note: ${bill.billNote}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Qty ${bill.totalCount} · Amt ${bill.totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...bill.rows.asMap().entries.map((entry) {
              final int index = entry.key;
              final row = entry.value;
              final amount =
                  BillRecord.readRowAmount(row['amount']).toStringAsFixed(2);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    '${row["type"]}  ${row["number"]}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    'Count ${row["count"]} · $amount',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  trailing: _canModifyBill
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_outlined,
                                  size: 20, color: themeColor),
                              onPressed: () => _editRow(index),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red.shade400),
                              onPressed: () => _deleteRow(index),
                            ),
                          ],
                        )
                      : null,
                ),
              );
            }),
            if (_directEdit && _canModifyBill) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _deleteBill,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  label: const Text('Delete Receipt'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

const Color kBookingSuperBtnColor = Color(0xFF51154A);
const Color kBookingBoxBtnColor = Color(0xFF275317);
const Color kBookingBothBtnColor = Color(0xFFFFC000);
const Color kBookingDigitBtn1 = Color(0xFF3C1642);
const Color kBookingDigitBtn2 = Color(0xFF086375);
const Color kBookingDigitBtn3 = Color(0xFF1DD3B0);
const Color kBookingDigitBtnAll = Color(0xFFAFFC41);

class TicketPage extends StatefulWidget {
  final String title;
  final String username;
  const TicketPage({super.key, required this.title, required this.username});
  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  String selectedOption = "3";
  String selectedTime = "LSK 3 PM";
  bool range = false;
  bool range2 = false;
  bool set = false;
  bool n100 = false;
  bool n111 = false;

  final TextEditingController numberController = TextEditingController();
  final TextEditingController countController = TextEditingController();
  final TextEditingController boxController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();
  final FocusNode numberFocusNode = FocusNode();
  final FocusNode countFocusNode = FocusNode();
  final FocusNode boxFocusNode = FocusNode();
  final List<Map<String, dynamic>> selectedEntries = [];
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  bool get isSingleDigitMode => selectedOption == "1";
  bool get isDoubleDigitMode => selectedOption == "2";
  bool get isTripleMode => selectedOption == "3";
  bool get isRangeMode => range || range2 || n100 || n111;

  /// Mode 3 with no pattern boxes selected (simple triple entry / Set Box path).
  bool get isTripleHundredDefault =>
      isTripleMode && !range && !range2 && !set && !n100 && !n111;

  bool get _drawBookingOpen =>
      DrawScheduleStore.isDrawBookingOpen(selectedTime, at: _now);

  bool get _salesBlocked => UserStore.isSalesBlocked(widget.username);

  void _showSalesBlockedMessage() {
    if (!mounted) return;
    showErrorSnack(context, AppMsg.salesBlocked);
  }

  bool _ensureCanSell() {
    if (!_salesBlocked) return true;
    _showSalesBlockedMessage();
    return false;
  }

  void _showDrawClosedMessage() {
    final msg =
        DrawScheduleStore.drawBookingBlockMessage(selectedTime, at: _now);
    if (msg == null || !mounted) return;
    showErrorSnack(context, msg);
  }

  /// Start / End / Count labels only when Range, Range 2, 100, or 111 is on.
  bool get _usesStartEndCountLayout => isRangeMode;
  bool get showThirdField => isTripleMode || isRangeMode;
  static const List<Color> _saveButtonGradient = [
    kAppBlue,
    kAppBlueDark,
  ];
  static const double _bookingToolbarHeight = 40;
  static const Color _bookingBarBlue = kAppBlue;
  static const Color _bookingDearGreen = Color(0xFF43A047);
  static const Color _bookingBoxPink = Color(0xFFD81B60);
  static const Color _bookingAllOrange = Color(0xFFEF6C00);
  static const Color _bookingSegmentAll = Color(0xFFD84315);

  /// Page chrome follows selected draw; action rows keep legacy colors.
  Color get _bookingPageColor => menuDrawColor(selectedTime);

  Color _bookingDrawButtonColor(String draw) => menuDrawColor(draw);

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _bookingTopPanel(),
            Expanded(child: _entriesList()),
            AnimatedPadding(
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: _bookingFooterBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookingTopPanel() {
    final pageColor = _bookingPageColor;
    return Container(
      width: double.infinity,
      color: pageColor,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(
        children: [
          if (!_drawBookingOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.zero,
                ),
                child: Text(
                  DrawScheduleStore.drawBookingBlockMessage(
                        selectedTime,
                        at: _now,
                      ) ??
                      AppMsg.bookingClosedFallback,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade900,
                  ),
                ),
              ),
            ),
          _bookingStatsRow(),
          const SizedBox(height: 6),
          _bookingDrawDropdown(),
          const SizedBox(height: 6),
          Row(
            children: [
              _patternCheckbox('Any', 'range'),
              _patternCheckbox('Set', 'set'),
              _patternCheckbox('100', '100'),
              _patternCheckbox('111', '111'),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: numberController,
                    focusNode: numberFocusNode,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF212121),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(countFocusNode),
                    onChanged: (value) {
                      setState(() {});
                      if ((isSingleDigitMode && value.isNotEmpty) ||
                          (isDoubleDigitMode && value.length >= 2) ||
                          (isTripleMode && value.length >= 3)) {
                        FocusScope.of(context).requestFocus(countFocusNode);
                      }
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      if (isSingleDigitMode) LengthLimitingTextInputFormatter(1),
                      if (isDoubleDigitMode) LengthLimitingTextInputFormatter(2),
                      if (isTripleMode) LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: _bookingInputDecoration(
                      _usesStartEndCountLayout ? 'Start' : 'Number',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: countController,
                    focusNode: countFocusNode,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF212121),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: _usesStartEndCountLayout
                        ? TextInputAction.next
                        : TextInputAction.done,
                    onSubmitted: (_) {
                      if (_usesStartEndCountLayout) {
                        FocusScope.of(context).requestFocus(boxFocusNode);
                      }
                    },
                    onChanged: (value) {
                      setState(() {});
                      if (_usesStartEndCountLayout && value.length >= 3) {
                        FocusScope.of(context).requestFocus(boxFocusNode);
                      }
                    },
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _bookingInputDecoration(
                      _usesStartEndCountLayout ? 'End' : 'Count',
                    ),
                  ),
                ),
                if (showThirdField) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: boxController,
                      focusNode: boxFocusNode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF212121),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _bookingInputDecoration(
                        _usesStartEndCountLayout ? 'Count' : 'B Count',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          _bookingSegmentedActionBar(),
        ],
      ),
    );
  }

  Widget _bookingStatsRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'COUNT :${_totalCount()}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        Expanded(
          child: Text(
            'Rs : ${_totalAmount().toStringAsFixed(1)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
        _headerDigitBtn('1'),
        _headerDigitBtn('2'),
        _headerDigitBtn('3'),
      ],
    );
  }

  Widget _headerDigitBtn(String text) {
    final bool isSelected = selectedOption == text;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: () {
          setState(() {
            selectedOption = text;
            if (isSingleDigitMode) {
              range = false;
              range2 = false;
              set = false;
              n100 = false;
              n111 = false;
              if (numberController.text.length > 1) {
                numberController.text = numberController.text.substring(0, 1);
              }
            }
            if (isDoubleDigitMode && numberController.text.length > 2) {
              numberController.text = numberController.text.substring(0, 2);
            }
            if (isTripleMode && numberController.text.length > 3) {
              numberController.text = numberController.text.substring(0, 3);
            }
            if (!isTripleMode) boxController.clear();
          });
        },
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? _bookingPageColor : Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: isSelected ? _bookingPageColor : Colors.white70,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: isSelected ? Colors.white : _bookingPageColor,
            ),
          ),
        ),
      ),
    );
  }

  void _openDrawPicker() {
    final allowed = _allowedDrawsForUser(widget.username);
    if (allowed.length <= 1) return;

    showAppDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < allowed.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == allowed.length - 1 ? 0 : 8,
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() => selectedTime = allowed[i]);
                          Navigator.pop(dialogContext);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            color: _bookingDrawButtonColor(allowed[i]),
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Text(
                            _drawDropdownLabel(allowed[i]),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bookingDrawDropdown() {
    final allowed = _allowedDrawsForUser(widget.username);
    final drawColor = _bookingDrawButtonColor(selectedTime);
    final labelStyle = const TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 16,
      color: Colors.white,
      letterSpacing: 0.2,
    );

    if (allowed.length <= 1) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: drawColor,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Text(
          _drawDropdownLabel(selectedTime),
          style: labelStyle,
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openDrawPicker,
        borderRadius: BorderRadius.zero,
        child: Ink(
          decoration: BoxDecoration(
            color: drawColor,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _drawDropdownLabel(selectedTime),
                    style: labelStyle,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Colors.white, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _drawDropdownLabel(String draw) => menuDrawShortLabel(draw);

  InputDecoration _bookingInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
    );
  }

  Widget _patternCheckbox(String label, String key) {
    final bool isSelected = _isPatternSelected(key);
    final bool disabled = isSingleDigitMode;
    return Expanded(
      child: InkWell(
        onTap: disabled
            ? null
            : () => _onExclusiveCheck(key, !isSelected),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: isSelected,
              onChanged: disabled
                  ? null
                  : (v) => _onExclusiveCheck(key, v ?? false),
              activeColor: Colors.white,
              checkColor: _bookingPageColor,
              side: BorderSide(
                color: disabled ? Colors.white38 : Colors.white,
                width: 1.5,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: disabled ? Colors.white54 : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entriesList() {
    if (selectedEntries.isEmpty) {
      return Center(
        child: Text(
          'No entries yet',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: selectedEntries.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey.shade300,
      ),
      itemBuilder: (context, index) {
        final row = selectedEntries[index];
        final type = row['type'] as String;
        final rowColor = _rowTypeColor(type);
        final amount = BillRecord.readRowAmount(row['amount']);
        final rowStyle = TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: rowColor,
          height: 1.0,
        );

        return SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    _rowTypeDisplay(type),
                    style: rowStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    row['number'] as String,
                    textAlign: TextAlign.center,
                    style: rowStyle,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    row['count'] as String,
                    textAlign: TextAlign.center,
                    style: rowStyle,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    amount.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: rowStyle,
                  ),
                ),
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    onPressed: _drawBookingOpen
                        ? () => setState(() => selectedEntries.removeAt(index))
                        : _showDrawClosedMessage,
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bookingFooterBar() {
    final canSave = selectedEntries.isNotEmpty &&
        _drawBookingOpen &&
        !_salesBlocked;
    final pageColor = _bookingPageColor;

    return Material(
      color: const Color(0xFFF0F2F5),
      elevation: 3,
      shadowColor: Colors.black45,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
          child: Row(
            children: [
              _bookingFooterIcon(
                icon: Icons.arrow_back,
                onPressed: () => Navigator.pop(context),
                iconColor: pageColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _bookingColorButton(
                  label: 'DELETE',
                  color: const Color(0xFFCC0000),
                  onPressed: () {
                    if (!_drawBookingOpen) {
                      _showDrawClosedMessage();
                      return;
                    }
                    setState(() {
                      numberController.clear();
                      countController.clear();
                      boxController.clear();
                      selectedEntries.clear();
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _bookingColorButton(
                  label: 'WHATSAPP',
                  color: const Color(0xFF25D366),
                  onPressed: _importEntriesFromClipboard,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _bookingColorButton(
                  label: 'SAVE',
                  color: canSave ? pageColor : const Color(0xFF90A4AE),
                  onPressed: canSave ? _saveCurrentBooking : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookingColorButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          height: double.infinity,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookingFooterIcon({
    IconData? icon,
    required VoidCallback onPressed,
    Widget? child,
    Color iconColor = Colors.white,
  }) {
    return SizedBox(
      width: 40,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: onPressed,
        icon: child ??
            Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
      ),
    );
  }

  String _drawActionLabel(String time) {
    switch (time.trim()) {
      case 'DEAR 1 PM':
        return '1 PM';
      case 'DEAR 6 PM':
        return '6 PM';
      case 'DEAR 8 PM':
        return '8 PM';
      case 'LSK 3 PM':
        return '3 PM';
      default:
        return time;
    }
  }

  String _actionBtnLabel(String text) {
    if (text == 'BOTH' || text == 'ALL') return 'ALL';
    final suffix = _actionBtnSuffix(text);
    final drawLabel = _drawActionLabel(selectedTime);
    if (suffix == 'SUPER') return '$drawLabel DEAR';
    if (suffix == 'BOX') return '$drawLabel BOX';
    return suffix;
  }

  String _rowTypeSuffix(String type) {
    final i = type.lastIndexOf('-');
    return i >= 0 ? type.substring(i + 1) : type;
  }

  String _rowDrawLetter(String draw) {
    if (draw.startsWith('LSK')) return 'L';
    return 'D';
  }

  int _rowDrawHour(String draw) {
    switch (draw.trim()) {
      case 'DEAR 1 PM':
        return 1;
      case 'DEAR 6 PM':
        return 6;
      case 'DEAR 8 PM':
        return 8;
      case 'LSK 3 PM':
        return 3;
      default:
        return 1;
    }
  }

  String _rowTypeDisplay(String type) {
    final suffix = _rowTypeSuffix(type);
    final drawLabel = _drawActionLabel(selectedTime);
    if (suffix == 'SUPER') return '$drawLabel DEAR';
    if (suffix == 'BOX') return '$drawLabel BOX';
    final letter = _rowDrawLetter(selectedTime);
    final hour = _rowDrawHour(selectedTime);
    return '$letter-$suffix-$hour';
  }

  Color _rowTypeColor(String type) {
    final suffix = _rowTypeSuffix(type);
    if (suffix == 'BOX' || suffix == 'B' || suffix == 'AC') {
      return _bookingBoxPink;
    }
    if (suffix == 'SUPER' || suffix == 'A' || suffix == 'AB') {
      return _bookingDearGreen;
    }
    if (suffix == 'C' || suffix == 'BC') {
      return _bookingAllOrange;
    }
    return _bookingAllOrange;
  }

  @override
  void initState() {
    super.initState();
    final allowed = _allowedDrawsForUser(widget.username);
    if (allowed.contains(widget.title.trim())) {
      selectedTime = widget.title.trim();
    } else if (allowed.isNotEmpty) {
      selectedTime = allowed.first;
    } else {
      selectedTime = _menuDrawForUser(widget.username, at: _now);
    }
    AppDrawTheme.refreshForUser(widget.username);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_salesBlocked) return;
      _showSalesBlockedMessage();
      Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    numberController.dispose();
    countController.dispose();
    boxController.dispose();
    customerNameController.dispose();
    numberFocusNode.dispose();
    countFocusNode.dispose();
    boxFocusNode.dispose();
    _clockTimer.cancel();
    super.dispose();
  }

  String get _selectedRangePattern {
    if (range2) return 'range2';
    if (range) return 'range';
    return 'none';
  }

  void _onRangePatternChanged(String? value) {
    if (isSingleDigitMode) return;
    setState(() {
      range = false;
      range2 = false;
      if (value == 'range' || value == 'range2') {
        set = false;
        n100 = false;
        n111 = false;
        if (value == 'range') range = true;
        if (value == 'range2') range2 = true;
      }
    });
  }

  Widget _compactOptionBox(String label, String key) {
    final bool isSelected = _isPatternSelected(key);
    final bool disabled = isSingleDigitMode;
    final Color gameColor = _timeColor(selectedTime);
    return InkWell(
      onTap: disabled ? null : () => _onExclusiveCheck(key, !isSelected),
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? gameColor : Colors.white,
          border:
              Border.all(color: isSelected ? gameColor : Colors.grey.shade400),
          borderRadius: BorderRadius.zero,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: disabled
                ? Colors.grey
                : (isSelected ? Colors.white : Colors.black87),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  bool _isPatternSelected(String key) {
    if (key == "range") return range;
    if (key == "range2") return range2;
    if (key == "set") return set;
    if (key == "100") return n100;
    if (key == "111") return n111;
    return false;
  }

  void _onExclusiveCheck(String key, bool? nextValue) {
    if (isSingleDigitMode) return;
    setState(() {
      range = false;
      range2 = false;
      set = false;
      n100 = false;
      n111 = false;
      if (nextValue != true) return;
      if (key == "range") range = true;
      if (key == "range2") range2 = true;
      if (key == "set") set = true;
      if (key == "100") n100 = true;
      if (key == "111") n111 = true;
    });
  }

  String _actionBtnSuffix(String text) {
    final i = text.lastIndexOf('-');
    return i >= 0 ? text.substring(i + 1) : text;
  }

  Color? _digitOptionBtnColor(String text) {
    if (text == 'ALL') return kBookingDigitBtnAll;
    switch (_actionBtnSuffix(text)) {
      case 'A':
      case 'AB':
        return kBookingDigitBtn1;
      case 'B':
      case 'BC':
        return kBookingDigitBtn2;
      case 'C':
      case 'AC':
        return kBookingDigitBtn3;
      default:
        return null;
    }
  }

  bool _actionBtnUsesDarkText(String text) {
    if (text == 'BOTH' || text == 'ALL') return true;
    final c = _digitOptionBtnColor(text);
    return c == kBookingDigitBtn3 || c == kBookingDigitBtnAll;
  }

  BoxDecoration _actionBtnDecoration(String text) {
    if (text == 'BOTH' || text == 'ALL') {
      return BoxDecoration(
        color: _bookingAllOrange,
        borderRadius: BorderRadius.zero,
      );
    }
    if (text.endsWith('-SUPER')) {
      return BoxDecoration(
        color: _bookingDearGreen,
        borderRadius: BorderRadius.zero,
      );
    }
    if (text.endsWith('-BOX')) {
      return BoxDecoration(
        color: _bookingBoxPink,
        borderRadius: BorderRadius.zero,
      );
    }
    final digitColor = _digitOptionBtnColor(text);
    if (digitColor != null) {
      return BoxDecoration(
        color: digitColor,
        borderRadius: BorderRadius.zero,
      );
    }
    return BoxDecoration(
      color: kAppBlue,
      borderRadius: BorderRadius.zero,
    );
  }

  Widget _bookingSegmentedActionBar() {
    final buttons = _modeButtons();
    return Container(
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            offset: const Offset(0, 2),
            blurRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Row(
          children: [
            for (var i = 0; i < buttons.length; i++)
              Expanded(
                child: _segmentActionBtn(
                  buttons[i],
                  showLeftDivider: i > 0,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _segmentActionBtn(String text, {required bool showLeftDivider}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _segmentBtnColor(text),
        border: showLeftDivider
            ? Border(
                left: BorderSide(
                  color: Colors.black.withValues(alpha: 0.22),
                  width: 1,
                ),
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onActionButtonPressed(text),
          child: SizedBox(
            height: 38,
            child: Center(
              child: Text(
                _segmentBtnLabel(text),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _segmentBtnLabel(String actionKey) {
    if (actionKey == 'ALL' || actionKey == 'BOTH') return 'ALL';
    final suffix = _actionBtnSuffix(actionKey);
    if (suffix == 'SUPER') return '${_drawActionLabel(selectedTime)} DEAR';
    if (suffix == 'BOX') return '${_drawActionLabel(selectedTime)} BOX';
    final letter = _rowDrawLetter(selectedTime);
    final hour = _rowDrawHour(selectedTime);
    return '$letter-$suffix-$hour';
  }

  Color _segmentBtnColor(String actionKey) {
    if (actionKey == 'ALL' || actionKey == 'BOTH') return _bookingSegmentAll;
    final suffix = _actionBtnSuffix(actionKey);
    if (suffix == 'SUPER' || suffix == 'A' || suffix == 'AB') {
      return _bookingDearGreen;
    }
    if (suffix == 'BOX' || suffix == 'B' || suffix == 'AC') {
      return _bookingBoxPink;
    }
    if (suffix == 'C' || suffix == 'BC') return _bookingAllOrange;
    return _bookingAllOrange;
  }

  void _onActionButtonPressed(String text) {
    if (!_drawBookingOpen) {
      _showDrawClosedMessage();
      return;
    }
    if (!_ensureCanSell()) return;
    final String inputNumber = numberController.text.trim();
    final String inputSecond = countController.text.trim();
    final String inputThird = boxController.text.trim();
    if (inputNumber.isEmpty || inputSecond.isEmpty) return;
    final bool isSimpleTriple = isTripleHundredDefault &&
        inputThird.isEmpty &&
        inputNumber.length == 3;
    final bool isSplitSuperBoxMode =
        isTripleMode && !isRangeMode && !isSimpleTriple;

    if (_usesStartEndCountLayout && !isSimpleTriple && inputThird.isEmpty) {
      return;
    }

    final int superCountInput = int.tryParse(inputSecond) ?? 0;
    final int boxCountInput = int.tryParse(inputThird) ?? 0;

    if (isSplitSuperBoxMode) {
      if (superCountInput <= 0) return;
      if ((text == "BOTH" || text.endsWith("-BOX")) && boxCountInput <= 0) {
        return;
      }
    }

    final int countVal = isSimpleTriple
        ? (int.tryParse(inputSecond) ?? 0)
        : (_usesStartEndCountLayout
            ? (int.tryParse(inputThird) ?? 0)
            : (int.tryParse(inputSecond) ?? 0));
    if (countVal <= 0) return;

    final List<String> types = _expandActionTypes(text);
    final List<String> numbers =
        isSimpleTriple ? [inputNumber.padLeft(3, "0")] : _expandNumbers();
    if (numbers.isEmpty) return;

    var pendingCount = 0;
    var pendingAmount = 0.0;
    final List<Map<String, dynamic>> pendingRows = [];
    for (final type in types) {
      for (final n in numbers) {
        int rowCount = countVal;
        if (isSplitSuperBoxMode) {
          if (type.endsWith("-SUPER")) {
            rowCount = superCountInput;
          } else if (type.endsWith("-BOX")) {
            rowCount = boxCountInput > 0 ? boxCountInput : superCountInput;
          } else {
            rowCount = superCountInput;
          }
        }
        if (rowCount <= 0) continue;
        final double amount = _rowAmountForType(type, rowCount);
        pendingCount += rowCount;
        pendingAmount += amount;
        pendingRows.add(_bookingRow(type, n, rowCount));
      }
    }
    if (pendingRows.isEmpty) return;
    if (!_validateUserLimits(
        addCount: pendingCount, addAmount: pendingAmount)) {
      return;
    }

    setState(() {
      for (final row in pendingRows.reversed) {
        selectedEntries.insert(0, row);
      }
      numberController.clear();
      countController.clear();
      boxController.clear();
    });
    FocusScope.of(context).requestFocus(numberFocusNode);
  }

  Widget actionBtn(String text) {
    return DecoratedBox(
      decoration: _actionBtnDecoration(text),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor:
              _actionBtnUsesDarkText(text) ? const Color(0xFF212121) : Colors.white,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _onActionButtonPressed(text),
        child: Text(
          _actionBtnLabel(text),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget bottomBtn(String text, Color color) {
    final String key = text.toUpperCase();
    final Color btnColor;
    switch (key) {
      case "CLEAR":
        btnColor = const Color(0xFF546E7A);
        break;
      case "HOME":
        btnColor = const Color(0xFFC62828);
        break;
      case "MESSAGE":
        btnColor = const Color(0xFF00695C);
        break;
      default:
        btnColor = color;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: btnColor,
        borderRadius: BorderRadius.zero,
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        onPressed: () {
          if (key == "CLEAR") {
            if (!_drawBookingOpen) {
              _showDrawClosedMessage();
              return;
            }
            setState(() {
              numberController.clear();
              countController.clear();
              boxController.clear();
              selectedEntries.clear();
            });
          } else if (key == "HOME") {
            Navigator.pop(context);
          } else if (key == "MESSAGE") {
            _importEntriesFromClipboard();
          }
        },
        child: Text(text),
      ),
    );
  }

  List<String> _modeButtons() {
    final code = _timeCode();
    if (selectedOption == "1") return ["$code-A", "$code-B", "$code-C", "ALL"];
    if (selectedOption == "2") {
      return ["$code-AB", "$code-AC", "$code-BC", "ALL"];
    }
    return ["$code-SUPER", "$code-BOX", "BOTH"];
  }

  Future<void> _importEntriesFromClipboard() async {
    if (!_drawBookingOpen) {
      _showDrawClosedMessage();
      return;
    }
    if (!_ensureCanSell()) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final String raw = (data?.text ?? "").trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      showErrorSnack(context, AppMsg.clipboardEmpty);
      return;
    }

    // Try WhatsApp Full Parser first
    if (raw.contains('\n') || raw.contains('*') || raw.length > 50) {
      if (_handleWhatsAppPaste(raw)) return;
    }

    final String cleaned = _stripWhatsAppMetadata(raw);
    final String inferredMode = _inferImportMode(cleaned);
    if (inferredMode == "2" && selectedOption != "2") {
      setState(() {
        selectedOption = "2";
        range = false;
        range2 = false;
        set = false;
        n100 = false;
        n111 = false;
      });
    } else if (inferredMode == "1" && selectedOption != "1") {
      setState(() {
        selectedOption = "1";
        range = false;
        range2 = false;
        set = false;
        n100 = false;
        n111 = false;
      });
    } else if (inferredMode == "3" && selectedOption != "3") {
      setState(() {
        selectedOption = "3";
        range = false;
        range2 = false;
        set = false;
        n100 = false;
        n111 = false;
      });
    }

    final List<Map<String, dynamic>> rows = _parseClipboardRows(raw);
    if (rows.isEmpty) {
      if (!mounted) return;
      showErrorSnack(context, AppMsg.clipboardFormatError);
      return;
    }

    setState(() {
      for (final row in rows.reversed) {
        selectedEntries.insert(0, row);
      }
      final String? lastNumber =
          rows.isNotEmpty ? rows.last["number"]?.toString() : null;
      final int len = lastNumber?.length ?? 0;
      if (len == 1) selectedOption = "1";
      if (len == 2) selectedOption = "2";
      if (len >= 3) selectedOption = "3";
    });

    if (!mounted) return;
    showSuccessSnack(context, AppMsg.entriesAdded(rows.length));
  }

  String _inferImportMode(String cleanedText) {
    if (_shouldAutoSwitchToDoubleDigit(cleanedText)) return "2";
    if (_shouldAutoSwitchToSingleDigit(cleanedText)) return "1";

    final List<String> tokens = RegExp(r'\d+')
        .allMatches(cleanedText)
        .map((m) => m.group(0) ?? "")
        .toList();
    if (tokens.isEmpty) return selectedOption;
    final List<String> numberTokens = [...tokens];
    if (numberTokens.length >= 2) {
      final int lastLen = numberTokens.last.length;
      final int maxPrev = numberTokens
          .take(numberTokens.length - 1)
          .map((t) => t.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      // Common pasted format: numbers...,count
      if (lastLen < maxPrev) numberTokens.removeLast();
    }

    final List<int> tokenLens = numberTokens
        .map((t) => t.length)
        .where((len) => len >= 1 && len <= 3)
        .toList();
    if (tokenLens.isEmpty) return selectedOption;

    final Set<int> kinds = tokenLens.toSet();
    if (kinds.length > 1) return "mixed";
    final int only = tokenLens.first;
    if (only == 1) return "1";
    if (only == 2) return "2";
    return "3";
  }

  bool _shouldAutoSwitchToDoubleDigit(String cleanedText) {
    final String text = cleanedText.toUpperCase();
    if (RegExp(r'\b(AB|BC|AC)\b').hasMatch(text)) return true;
    if (RegExp(r'AB[^A-Z0-9]*BC[^A-Z0-9]*AC').hasMatch(text)) return true;
    for (final m in RegExp(r'[A-Z]+').allMatches(text)) {
      final String token = m.group(0) ?? "";
      if (token.isEmpty) continue;
      final Set<String> chars = token.split('').toSet();
      final bool allbordLike = chars.contains('A') &&
          chars.contains('B') &&
          chars.contains('O') &&
          chars.contains('R') &&
          chars.contains('D') &&
          chars.contains('L');
      if (allbordLike || token.contains('NORD')) return true;
    }
    return false;
  }

  bool _shouldAutoSwitchToSingleDigit(String cleanedText) {
    final String text = cleanedText.toUpperCase();
    for (final m in RegExp(r'[A-Z]+').allMatches(text)) {
      final String token = m.group(0) ?? "";
      if (token.isEmpty) continue;
      // AB/BC/AC pair tokens are 2-digit group indicators, not 1-digit mode.
      if (token == "AB" ||
          token == "BA" ||
          token == "BC" ||
          token == "CB" ||
          token == "AC" ||
          token == "CA") {
        continue;
      }
      final Set<String> chars = token.split('').toSet();
      final String normalized = token;
      if (chars.contains('A') && chars.contains('B') && chars.contains('C')) {
        return true;
      }
      if (chars.length == 1 &&
          (chars.contains('A') || chars.contains('B') || chars.contains('C'))) {
        return true;
      }
      final bool allbordLike = chars.contains('A') &&
              chars.contains('B') &&
              chars.contains('O') &&
              chars.contains('R') &&
              chars.contains('D') &&
              chars.contains('L') ||
          (normalized.startsWith('ALL') &&
              (normalized.contains('NORD') ||
                  normalized.contains('ORD') ||
                  normalized.contains('BORD')));
      if (allbordLike) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _parseClipboardRows(String raw) {
    final String cleanedRaw = _stripWhatsAppMetadata(raw);
    final List<Map<String, dynamic>> parsed = [];
    final int digits =
        selectedOption == "1" ? 1 : (selectedOption == "2" ? 2 : 3);
    final String code = _timeCode();
    final RegExp typeRx = RegExp(
      r'(DEAR1|DEAR6|DEAR8|LSK3)-(A|B|C|AB|BC|AC|SUPER|BOX)',
      caseSensitive: false,
    );
    final RegExp pairRx = RegExp(
      '(?<!\\d)(\\d{1,3})(?!\\d)(?:'
      '\\s*[\\(\\[\\{]\\s*(\\d{1,5})\\s*[\\)\\]\\}]'
      '|\\s*[^0-9]{1,30}\\s*(\\d{1,5})'
      '|\\s+(\\d{1,5})'
      ')',
    );
    final RegExp lineBulkRx = RegExp(
      '^((?:\\d{$digits}\\s*[^0-9A-Za-z\\s]+\\s*)+\\d{$digits})\\s*[^0-9A-Za-z\\s]+\\s*(\\d{1,5})\$',
    );

    void addImportedRow(String type, String number, int count,
        {bool forceSetExpand = false}) {
      if (count <= 0) return;
      for (final expanded
          in _expandImportedNumbers(number, forceSetExpand: forceSetExpand)) {
        parsed.add(_bookingRow(type, expanded, count));
      }
    }

    final List<String> lines = cleanedRaw
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final String normalized =
        lines.join(" ").replaceAll(RegExp(r'\s+'), ' ').trim();
    final String defaultType = _defaultImportedType();
    final List<String> standaloneNumbers = [];
    int? trailingLineCount;

    // Special keyword rules:
    // - "...(set box)" -> 3-digit SET style import (6 permutations)
    // - "...(direct)"  -> 3-digit SUPER direct import
    // - "A box :8:10"  -> 1-digit A-board import
    bool handledKeywordLines = false;
    for (final line in lines) {
      final String lower = line.toLowerCase();
      final Iterable<Match> pairMatches =
          RegExp(r'(\d{1,3})\s*[:]\s*(\d{1,5})').allMatches(line);
      if (pairMatches.isEmpty) continue;

      if (lower.contains('set box') || lower.contains('setbox')) {
        for (final m in pairMatches) {
          final String number = (m.group(1) ?? "").trim();
          final int count = int.tryParse((m.group(2) ?? "").trim()) ?? 0;
          if (number.length == 3 && count > 0) {
            addImportedRow("$code-SUPER", number.padLeft(3, "0"), count,
                forceSetExpand: true);
            handledKeywordLines = true;
          }
        }
        continue;
      }

      if (lower.contains('direct')) {
        for (final m in pairMatches) {
          final String number = (m.group(1) ?? "").trim();
          final int count = int.tryParse((m.group(2) ?? "").trim()) ?? 0;
          if (number.length == 3 && count > 0) {
            addImportedRow("$code-SUPER", number.padLeft(3, "0"), count);
            handledKeywordLines = true;
          }
        }
        continue;
      }

      if (RegExp(r'\ba\s*box\b', caseSensitive: false).hasMatch(line)) {
        for (final m in pairMatches) {
          final String number = (m.group(1) ?? "").trim();
          final int count = int.tryParse((m.group(2) ?? "").trim()) ?? 0;
          if (number.length == 1 && count > 0) {
            addImportedRow("$code-A", number, count);
            handledKeywordLines = true;
          }
        }
      }
    }
    if (handledKeywordLines && parsed.isNotEmpty) return parsed;

    final List<String> modeTokens = RegExp(r'\d+')
        .allMatches(normalized)
        .map((m) => m.group(0) ?? "")
        .toList();
    if (modeTokens.length >= 2) {
      final int lastLen = modeTokens.last.length;
      final int maxPrev = modeTokens
          .take(modeTokens.length - 1)
          .map((t) => t.length)
          .fold<int>(0, (a, b) => a > b ? a : b);
      if (lastLen < maxPrev) modeTokens.removeLast();
    }
    final Set<int> digitKinds = modeTokens
        .map((t) => t.length)
        .where((len) => len >= 1 && len <= 3)
        .toSet();
    final bool hasMixedDigits = digitKinds.length > 1;

    if (hasMixedDigits) {
      // Mixed mode: infer type by each number's digit length.
      // 1-digit -> A, 2-digit -> AB, 3-digit -> SUPER.
      String? pendingSingleGroup; // A / B / C / ABC / ALLBORD
      String? pendingDoubleGroup; // AB / BC / AC / ALLBORD

      String? resolveLooseSingleGroup(String token) {
        final String letters =
            token.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
        if (letters.isEmpty) return null;
        final Set<String> chars = letters.split('').toSet();
        if (chars.contains('A') && chars.contains('B') && chars.contains('C')) {
          return "ABC";
        }
        final bool looksLikeAllbord = (chars.contains('A') &&
                chars.contains('B') &&
                chars.contains('O') &&
                chars.contains('R') &&
                chars.contains('D') &&
                chars.contains('L')) ||
            (letters.startsWith('ALL') &&
                (letters.contains('NORD') ||
                    letters.contains('ORD') ||
                    letters.contains('BORD'))) ||
            letters.contains('BORD') ||
            letters.contains('NORD');
        if (looksLikeAllbord) return "ALLBORD";
        if (chars.length == 1 && chars.contains('A')) return "A";
        if (chars.length == 1 && chars.contains('B')) return "B";
        if (chars.length == 1 && chars.contains('C')) return "C";
        return null;
      }

      String? resolveLooseDoubleGroup(String token) {
        final String letters =
            token.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
        if (letters.isEmpty) return null;
        final Set<String> chars = letters.split('').toSet();
        if (letters == "AB" || letters == "BA") return "AB";
        if (letters == "BC" || letters == "CB") return "BC";
        if (letters == "AC" || letters == "CA") return "AC";
        final bool hasAllPairTags = letters.contains("AB") &&
            letters.contains("BC") &&
            letters.contains("AC");
        if (hasAllPairTags) return "ALLBORD";
        final bool looksLikeAllbord = (chars.contains('A') &&
                chars.contains('B') &&
                chars.contains('O') &&
                chars.contains('R') &&
                chars.contains('D') &&
                chars.contains('L')) ||
            letters.contains('BORD') ||
            letters.contains('NORD');
        if (looksLikeAllbord) return "ALLBORD";
        return null;
      }

      List<String> singleTypesForGroup(String group) {
        if (group == "A") return ["$code-A"];
        if (group == "B") return ["$code-B"];
        if (group == "C") return ["$code-C"];
        return ["$code-A", "$code-B", "$code-C"];
      }

      List<String> doubleTypesForGroup(String group) {
        if (group == "AB") return ["$code-AB"];
        if (group == "BC") return ["$code-BC"];
        if (group == "AC") return ["$code-AC"];
        return ["$code-AB", "$code-BC", "$code-AC"];
      }

      for (final line in lines) {
        final String compact =
            line.replaceAll(RegExp(r'\s+'), '').toUpperCase();
        final bool forceSetLikeInMixed = RegExp(
          r'(set\s*box|srt\s*box|sat\s*box|setbox|srtbox|satbox|\bbox\b)',
          caseSensitive: false,
        ).hasMatch(line);
        final String? wholeDoubleGroup = resolveLooseDoubleGroup(compact);
        if (wholeDoubleGroup != null && !RegExp(r'\d').hasMatch(compact)) {
          pendingDoubleGroup = wholeDoubleGroup;
          continue;
        }
        final String? wholeSingleGroup = resolveLooseSingleGroup(compact);
        if (wholeSingleGroup != null && !RegExp(r'\d').hasMatch(compact)) {
          pendingSingleGroup = wholeSingleGroup;
          continue;
        }

        // Mixed text split support:
        // 123..15*5 / 234.15*5 => number, superCount, boxCount
        final List<String> splitTokens =
            RegExp(r'\d+').allMatches(line).map((m) => m.group(0)!).toList();
        if (splitTokens.length == 3 && splitTokens.first.length == 3) {
          final String number = splitTokens[0];
          final int superCount = int.tryParse(splitTokens[1]) ?? 0;
          final int boxCount = int.tryParse(splitTokens[2]) ?? 0;
          if (superCount > 0 || boxCount > 0) {
            addImportedRow("$code-SUPER", number, superCount);
            addImportedRow("$code-BOX", number, boxCount);
            continue;
          }
        }

        bool handledBySinglePrefix = false;
        final RegExp singlePrefixedRx = RegExp(
            r'([A-Z]+)[^0-9]*([0-9])[^0-9]*([0-9]{1,5})',
            caseSensitive: false);
        for (final m in singlePrefixedRx.allMatches(compact)) {
          final String? grp = resolveLooseSingleGroup(m.group(1) ?? "");
          if (grp == null) continue;
          final String number = m.group(2) ?? "";
          final int count = int.tryParse(m.group(3) ?? "0") ?? 0;
          if (number.isEmpty || count <= 0) continue;
          for (final type in singleTypesForGroup(grp)) {
            addImportedRow(type, number, count);
          }
          pendingSingleGroup = grp;
          handledBySinglePrefix = true;
        }
        if (handledBySinglePrefix) continue;

        bool handledByDoublePrefix = false;
        final RegExp doublePrefixedRx = RegExp(
            r'([A-Z]+)[^0-9]*([0-9]{2})[^0-9]*([0-9]{1,5})',
            caseSensitive: false);
        for (final m in doublePrefixedRx.allMatches(compact)) {
          final String? grp = resolveLooseDoubleGroup(m.group(1) ?? "");
          if (grp == null) continue;
          final String number = m.group(2) ?? "";
          final int count = int.tryParse(m.group(3) ?? "0") ?? 0;
          if (number.isEmpty || count <= 0) continue;
          for (final t in doubleTypesForGroup(grp)) {
            addImportedRow(t, number, count);
          }
          pendingDoubleGroup = grp;
          handledByDoublePrefix = true;
        }
        if (handledByDoublePrefix) continue;

        String activeType = defaultType;
        final List<Match> typeMatches = typeRx.allMatches(line).toList();
        int typeIndex = 0;
        for (final match in pairRx.allMatches(line)) {
          while (typeIndex < typeMatches.length &&
              typeMatches[typeIndex].start < match.start) {
            final Match t = typeMatches[typeIndex];
            activeType =
                "${t.group(1)!.toUpperCase()}-${t.group(2)!.toUpperCase()}";
            typeIndex++;
          }
          final String numberRaw = (match.group(1) ?? "");
          final int numberDigits = numberRaw.length;
          if (numberDigits < 1 || numberDigits > 3) continue;
          final String number = numberRaw.padLeft(numberDigits, "0");
          final String countText =
              match.group(2) ?? match.group(3) ?? match.group(4) ?? "0";
          final int count = int.tryParse(countText.trim()) ?? 0;
          if (numberDigits == 1 && pendingSingleGroup != null) {
            for (final t in singleTypesForGroup(pendingSingleGroup)) {
              addImportedRow(t, number, count);
            }
          } else if (numberDigits == 2 && pendingDoubleGroup != null) {
            for (final t in doubleTypesForGroup(pendingDoubleGroup)) {
              addImportedRow(t, number, count);
            }
          } else {
            final String inferredType = typeMatches.isNotEmpty
                ? activeType
                : _defaultImportedTypeForDigits(numberDigits);
            addImportedRow(
              inferredType,
              number,
              count,
              forceSetExpand: forceSetLikeInMixed && numberDigits == 3,
            );
          }
        }
      }

      if (parsed.isEmpty) {
        final List<String> allTokens = RegExp(r'\d+')
            .allMatches(normalized)
            .map((m) => m.group(0)!)
            .toList();
        if (allTokens.length >= 2) {
          final int commonCount = int.tryParse(allTokens.last) ?? 0;
          if (commonCount > 0) {
            for (int i = 0; i < allTokens.length - 1; i++) {
              final String n = allTokens[i];
              final int d = n.length;
              if (d < 1 || d > 3) continue;
              if (d == 2 && pendingDoubleGroup != null) {
                for (final t in doubleTypesForGroup(pendingDoubleGroup)) {
                  addImportedRow(t, n.padLeft(d, "0"), commonCount);
                }
              } else {
                addImportedRow(
                  _defaultImportedTypeForDigits(d),
                  n.padLeft(d, "0"),
                  commonCount,
                );
              }
            }
          }
        }
      }

      if (parsed.isNotEmpty) return parsed;
    }

    if (selectedOption == "2") {
      String? pendingGroup; // AB / BC / AC / ALLBORD
      final List<String> groupNumbers = [];
      int? groupCount;

      String? resolveDoubleGroup(String token) {
        final String letters =
            token.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
        if (letters.isEmpty) return null;
        final Set<String> chars = letters.split('').toSet();
        if (letters == "AB" || letters == "BA") return "AB";
        if (letters == "BC" || letters == "CB") return "BC";
        if (letters == "AC" || letters == "CA") return "AC";
        final bool hasAllPairTags = letters.contains("AB") &&
            letters.contains("BC") &&
            letters.contains("AC");
        if (hasAllPairTags) return "ALLBORD";
        final bool allbordLike = chars.contains('A') &&
            chars.contains('B') &&
            chars.contains('O') &&
            chars.contains('R') &&
            chars.contains('D') &&
            chars.contains('L');
        if (allbordLike ||
            letters.contains("NORD") ||
            letters.contains("BORD")) {
          return "ALLBORD";
        }
        return null;
      }

      List<String> typesForDoubleGroup(String group) {
        if (group == "AB") return ["$code-AB"];
        if (group == "BC") return ["$code-BC"];
        if (group == "AC") return ["$code-AC"];
        return ["$code-AB", "$code-BC", "$code-AC"];
      }

      for (final rawLine in lines) {
        final String line = rawLine.trim();
        if (line.isEmpty) continue;
        final String compact =
            line.replaceAll(RegExp(r'\s+'), '').toUpperCase();
        final String? wholeGroup = resolveDoubleGroup(compact);
        if (wholeGroup != null && !RegExp(r'\d').hasMatch(compact)) {
          pendingGroup = wholeGroup;
          continue;
        }

        bool matchedThisLine = false;
        final RegExp prefixedRx = RegExp(
            r'([A-Z]+)[^0-9]*([0-9]{2})[^0-9]*([0-9]{1,5})',
            caseSensitive: false);
        for (final m in prefixedRx.allMatches(compact)) {
          final String? group = resolveDoubleGroup(m.group(1) ?? "");
          if (group == null) continue;
          final String number = m.group(2) ?? "";
          final int count = int.tryParse(m.group(3) ?? "0") ?? 0;
          if (count <= 0) continue;
          for (final type in typesForDoubleGroup(group)) {
            addImportedRow(type, number, count);
          }
          matchedThisLine = true;
        }
        if (matchedThisLine) continue;

        // Two-digit number rows must be captured BEFORE generic count row check.
        if (RegExp(r'^\d{2}$').hasMatch(compact)) {
          groupNumbers.add(compact);
          continue;
        }
        if (RegExp(r'^\d{1,5}$').hasMatch(compact)) {
          groupCount = int.tryParse(compact);
          continue;
        }
        if (!RegExp(r'[A-Za-z]').hasMatch(compact)) {
          final List<String> twoDigitTokens = RegExp(r'\d+')
              .allMatches(compact)
              .map((x) => x.group(0)!)
              .where((n) => n.length == 2)
              .toList();
          if (twoDigitTokens.length >= 2) {
            groupNumbers.addAll(twoDigitTokens);
          }
        }
      }

      if (groupNumbers.isNotEmpty && (groupCount ?? 0) > 0) {
        final String group = pendingGroup ?? "ALLBORD";
        for (final n in groupNumbers) {
          for (final type in typesForDoubleGroup(group)) {
            addImportedRow(type, n, groupCount!);
          }
        }
      }

      if (parsed.isNotEmpty) return parsed;
    }

    // 1-digit dedicated rules:
    // A.5.5 / B.5.5 / C5.5 / ABC.5,5 / ALLBORD.5.5
    // ABC (line) + 1.5 (next line) etc.
    if (selectedOption == "1") {
      String? pendingGroup; // A / B / C / ABC / ALLBORD

      String? resolveLooseGroup(String token) {
        final String letters =
            token.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
        if (letters.isEmpty) return null;
        final Set<String> chars = letters.split('').toSet();
        final String normalized = letters;

        // Any token containing A+B+C (in any order) is treated as ABC.
        if (chars.contains('A') && chars.contains('B') && chars.contains('C')) {
          return "ABC";
        }

        // Loose ALLBORD detection for spelling/order variations.
        // Ex: ALLBORD, ALLBOARD, ALBORD, ABOLRD...
        final bool looksLikeAllbord = (chars.contains('A') &&
                chars.contains('B') &&
                chars.contains('O') &&
                chars.contains('R') &&
                chars.contains('D') &&
                chars.contains('L')) ||
            (normalized.startsWith('ALL') &&
                (normalized.contains('NORD') ||
                    normalized.contains('ORD') ||
                    normalized.contains('BORD'))) ||
            normalized.contains('BORD') ||
            normalized.contains('NORD');
        if (looksLikeAllbord) return "ALLBORD";

        if (chars.length == 1 && chars.contains('A')) return "A";
        if (chars.length == 1 && chars.contains('B')) return "B";
        if (chars.length == 1 && chars.contains('C')) return "C";
        return null;
      }

      List<String> typesForGroup(String group) {
        final g = group.toUpperCase();
        if (g == "A") return ["$code-A"];
        if (g == "B") return ["$code-B"];
        if (g == "C") return ["$code-C"];
        return ["$code-A", "$code-B", "$code-C"]; // ABC / ALLBORD
      }

      for (final rawLine in lines) {
        final String line = rawLine.trim();
        if (line.isEmpty) continue;
        final String compact =
            line.replaceAll(RegExp(r'\s+'), '').toUpperCase();
        final RegExp prefixedRx = RegExp(
          r'([A-Z]+)[^0-9]*([0-9])[^0-9]*([0-9]{1,5})',
          caseSensitive: false,
        );
        final RegExp plainRx = RegExp(r'([0-9])[^0-9]*([0-9]{1,5})');

        final String? wholeGroup = resolveLooseGroup(compact);
        if (wholeGroup != null && !RegExp(r'\d').hasMatch(compact)) {
          pendingGroup = wholeGroup;
          continue;
        }

        bool matchedThisLine = false;

        for (final prefixed in prefixedRx.allMatches(compact)) {
          final String grpToken = (prefixed.group(1) ?? "").toUpperCase();
          final String? grp = resolveLooseGroup(grpToken);
          if (grp == null) continue;
          final String number = prefixed.group(2) ?? "";
          final int count = int.tryParse(prefixed.group(3) ?? "0") ?? 0;
          if (number.isNotEmpty && count > 0) {
            for (final type in typesForGroup(grp)) {
              addImportedRow(type, number, count);
            }
            matchedThisLine = true;
          }
        }
        if (matchedThisLine) continue;

        for (final plain in plainRx.allMatches(compact)) {
          final String number = plain.group(1) ?? "";
          final int count = int.tryParse(plain.group(2) ?? "0") ?? 0;
          if (number.isNotEmpty && count > 0) {
            final String group = pendingGroup ?? "A";
            for (final type in typesForGroup(group)) {
              addImportedRow(type, number, count);
            }
            matchedThisLine = true;
          }
        }
        if (matchedThisLine) continue;
      }

      if (parsed.isNotEmpty) return parsed;
    }

    // Process each line independently so mixed-rule messages work together.
    for (final line in lines) {
      bool handled = false;

      // SUPER/BOX split per line (e.g. 123.1.1 / 123 1.1).
      // Apply only when the line contains exactly 3 numeric tokens, so that
      // bulk lists like 000,100,200,...,900-3 don't get misclassified.
      final List<String> splitTokens =
          RegExp(r'\d+').allMatches(line).map((m) => m.group(0)!).toList();
      if (splitTokens.length == 3 && splitTokens.first.length == digits) {
        final String number = splitTokens[0].padLeft(digits, "0");
        final int superCount = int.tryParse(splitTokens[1]) ?? 0;
        final int boxCount = int.tryParse(splitTokens[2]) ?? 0;
        if (superCount > 0 || boxCount > 0) {
          addImportedRow("$code-SUPER", number, superCount);
          addImportedRow("$code-BOX", number, boxCount);
          handled = true;
        }
      }
      if (handled) continue;

      // Bulk list in one line with trailing count.
      if (!RegExp(r'[A-Za-z]').hasMatch(line)) {
        final Match? bulk = lineBulkRx.firstMatch(line);
        if (bulk != null) {
          final int count = int.tryParse((bulk.group(2) ?? "").trim()) ?? 0;
          final List<String> nums = RegExp('\\d{$digits}')
              .allMatches(bulk.group(1) ?? "")
              .map((x) => x.group(0)!)
              .toList();
          if (count > 0 && nums.length >= 2) {
            for (final n in nums) {
              addImportedRow(defaultType, n.padLeft(digits, "0"), count);
            }
            continue;
          }
        }
      }

      // Pure standalone number line (for "last line count" rule).
      if (RegExp('^\\d{$digits}\$').hasMatch(line)) {
        standaloneNumbers.add(line.padLeft(digits, "0"));
        continue;
      }

      // Space-separated pure number list line:
      // 000 002 003 ... 099
      // Keep these numbers for trailing common-count rule.
      if (!RegExp(r'[A-Za-z]').hasMatch(line)) {
        final List<String> spaceTokens = line
            .split(RegExp(r'\s+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (spaceTokens.length >= 2 &&
            spaceTokens.every((t) => RegExp('^\\d{$digits}\$').hasMatch(t))) {
          for (final t in spaceTokens) {
            standaloneNumbers.add(t.padLeft(digits, "0"));
          }
          continue;
        }
      }

      // Candidate trailing count line.
      if (RegExp(r'^\d{1,5}$').hasMatch(line)) {
        trailingLineCount = int.tryParse(line);
        continue;
      }

      // Generic number-count pairs in text.
      String activeType = defaultType;
      final List<String> lineNumberTokens =
          RegExp(r'\d+').allMatches(line).map((m) => m.group(0)!).toList();
      final bool looseSetLikeLine = selectedOption == "3" &&
          lineNumberTokens.length == 2 &&
          lineNumberTokens.first.length == digits &&
          RegExp(r'[A-Za-z]').hasMatch(line);
      final bool forceSetExpand = selectedOption == "3" &&
          (looseSetLikeLine ||
              RegExp(r'(set\s*box|srt\s*box|sat\s*box|setbox|srtbox|satbox|\bbox\b)',
                      caseSensitive: false)
                  .hasMatch(line));
      final List<Match> typeMatches = typeRx.allMatches(line).toList();
      int typeIndex = 0;
      for (final match in pairRx.allMatches(line)) {
        while (typeIndex < typeMatches.length &&
            typeMatches[typeIndex].start < match.start) {
          final Match t = typeMatches[typeIndex];
          activeType =
              "${t.group(1)!.toUpperCase()}-${t.group(2)!.toUpperCase()}";
          typeIndex++;
        }
        final String number = (match.group(1) ?? "").padLeft(digits, "0");
        final int numberDigits = (match.group(1) ?? "").length;
        if (numberDigits < 1 || numberDigits > 3) continue;
        final String countText =
            match.group(2) ?? match.group(3) ?? match.group(4) ?? "0";
        final int count = int.tryParse(countText.trim()) ?? 0;
        final String inferredType = typeMatches.isNotEmpty
            ? activeType
            : _defaultImportedTypeForDigits(numberDigits);
        addImportedRow(inferredType, number, count,
            forceSetExpand: forceSetExpand && numberDigits == 3);
        handled = true;
      }

      if (!handled && !RegExp(r'[A-Za-z]').hasMatch(line)) {
        // Store additional digit tokens for fallback common-count application.
        for (final t
            in RegExp(r'\d+').allMatches(line).map((m) => m.group(0)!)) {
          if (t.length == digits) {
            standaloneNumbers.add(t.padLeft(digits, "0"));
          }
        }
      }
    }

    // Apply trailing line count to collected standalone numbers.
    if (standaloneNumbers.isNotEmpty && (trailingLineCount ?? 0) > 0) {
      for (final n in standaloneNumbers) {
        addImportedRow(defaultType, n, trailingLineCount!);
      }
      return parsed;
    }

    // Global common-count fallback for single-line/mixed separators.
    if (parsed.isEmpty) {
      final List<String> allTokens = RegExp(r'\d+')
          .allMatches(normalized)
          .map((m) => m.group(0)!)
          .toList();
      if (allTokens.length >= 2) {
        final int commonCount = int.tryParse(allTokens.last) ?? 0;
        if (commonCount > 0) {
          for (int i = 0; i < allTokens.length - 1; i++) {
            final t = allTokens[i];
            if (t.isNotEmpty && t.length <= 3) {
              final String inferredType =
                  _defaultImportedTypeForDigits(t.length);
              addImportedRow(
                  inferredType, t.padLeft(t.length, "0"), commonCount);
            }
          }
        }
      }
    }
    return parsed;
  }

  List<String> _expandImportedNumbers(String number,
      {bool forceSetExpand = false}) {
    // If SET is selected in 3-digit mode, imported numbers should follow
    // the same permutation rule as manual booking (up to 6 entries).
    final bool shouldExpandSet = number.length == 3 &&
        (forceSetExpand || (selectedOption == "3" && set));
    if (!shouldExpandSet) {
      return [number];
    }
    final a = number[0], b = number[1], c = number[2];
    return <String>{
      "$a$b$c",
      "$b$c$a",
      "$c$a$b",
      "$c$b$a",
      "$a$c$b",
      "$b$a$c",
    }.toList();
  }

  String _stripWhatsAppMetadata(String input) {
    final List<String> out = [];
    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      String line = rawLine.trim();
      if (line.isEmpty) continue;

      // Ignore pure WhatsApp metadata lines:
      // [11:08 pm, 22/04/2026] name:
      if (RegExp(r'^\[[^\]]+\]\s*[^:]*:\s*$').hasMatch(line)) {
        continue;
      }

      // If metadata and content are in same line, keep only content after colon.
      final RegExp withText = RegExp(r'^\[[^\]]+\]\s*[^:]*:\s*(.+)$');
      final Match? m = withText.firstMatch(line);
      if (m != null) {
        line = (m.group(1) ?? "").trim();
        if (line.isEmpty) continue;
      }

      out.add(line);
    }
    return out.join('\n');
  }

  String _defaultImportedType() {
    return _defaultImportedTypeForDigits(
        selectedOption == "1" ? 1 : (selectedOption == "2" ? 2 : 3));
  }

  String _defaultImportedTypeForDigits(int digits) {
    final code = _timeCode();
    if (digits <= 1) return "$code-A";
    if (digits == 2) return "$code-AB";
    return "$code-SUPER";
  }

  List<String> _expandActionTypes(String action) {
    final code = _timeCode();
    if (action == "BOTH") return ["$code-SUPER", "$code-BOX"];
    if (action == "ALL") {
      if (selectedOption == "1") return ["$code-A", "$code-B", "$code-C"];
      if (selectedOption == "2") return ["$code-AB", "$code-BC", "$code-AC"];
    }
    return [action];
  }

  String _timeCode() {
    switch (selectedTime) {
      case "DEAR 1 PM":
        return "DEAR1";
      case "DEAR 6 PM":
        return "DEAR6";
      case "DEAR 8 PM":
        return "DEAR8";
      case "LSK 3 PM":
      default:
        return "LSK3";
    }
  }

  List<String> _expandNumbers() {
    if (n111) {
      final int? start = int.tryParse(numberController.text.trim());
      final int? end = int.tryParse(countController.text.trim());
      if (start == null || end == null || start > end) return [];
      final values = <String>[];
      for (int i = 0; i <= 999; i += 111) {
        if (i >= start && i <= end) {
          values.add(i.toString().padLeft(3, "0"));
        }
      }
      return values;
    }

    if (n100) {
      final int? start = int.tryParse(numberController.text.trim());
      final int? end = int.tryParse(countController.text.trim());
      if (start == null || end == null || start > end) return [];
      final values = <String>[];
      int current = start;
      while (current <= end) {
        values.add(current.toString().padLeft(3, "0"));
        current += 100;
      }
      final String endStr = end.toString().padLeft(3, "0");
      // 111–999: 111…911 (9) + 999 → 10 lines × ₹10 × count 1 = ₹100
      if (!values.contains(endStr) && end == 999) {
        values.add(endStr);
      }
      return values;
    }

    if (range2) {
      final int? start = int.tryParse(numberController.text.trim());
      final int? end = int.tryParse(countController.text.trim());
      if (start == null || end == null || start > end) return [];
      final values = <String>[];
      int current = start;
      while (current <= end) {
        final t = current.toString().padLeft(3, "0");
        if (t.length <= 3) values.add(t);
        current += 10;
      }
      return values;
    }

    if (range) {
      final int? start = int.tryParse(numberController.text.trim());
      final int? end = int.tryParse(countController.text.trim());
      if (start == null || end == null || start > end) return [];
      final startText = start.toString().padLeft(3, "0");
      final endText = end.toString().padLeft(3, "0");
      if (startText.substring(1) == endText.substring(1)) {
        final suffix = startText.substring(1);
        return List<String>.generate(10, (i) => "$i$suffix");
      }
      return List<String>.generate(
          end - start + 1, (i) => (start + i).toString().padLeft(3, "0"));
    }

    final input = numberController.text.trim();
    if (set && input.length == 3) {
      final a = input[0], b = input[1], c = input[2];
      return <String>{
        "$a$b$c",
        "$b$c$a",
        "$c$a$b",
        "$c$b$a",
        "$a$c$b",
        "$b$a$c"
      }.toList();
    }
    return [input];
  }

  double _rowAmountForRate(double rate, int count) {
    if (count <= 0 || rate <= 0) return 0;
    final agent = UserStore.byUsername(widget.username);
    final scheme = PriceListStore.gameRatesFor(widget.username).billingScheme;
    return applyBillingSchemeAmount(
      bookingAmountFromRate(rate, count),
      scheme,
    );
  }

  double _rowAmountForType(String type, int count) {
    if (count <= 0) return 0;
    final agent = UserStore.byUsername(widget.username);
    return effectiveRowAmountForUser(
      username: widget.username,
      type: type,
      count: count,
      role: agent?.role ?? AppSession.role,
      rateSetId: agent?.rateSetId,
    );
  }

  double _rateForType(String type) {
    final agent = UserStore.byUsername(widget.username);
    return effectiveSaleRateForUser(
      username: widget.username,
      type: type,
      role: agent?.role ?? AppSession.role,
      rateSetId: agent?.rateSetId,
    );
  }

  String _formatBookingRate(double rate) => rate.toStringAsFixed(2);

  double _rowRateFromMap(Map<String, dynamic> row) {
    if (row.containsKey('rate')) {
      return BillRecord.readRowRate(row['rate']);
    }
    return _rateForType(row['type'].toString());
  }

  Map<String, dynamic> _bookingRow(String type, String number, int count) {
    final rate = _rateForType(type);
    return {
      'type': type,
      'number': number,
      'count': count.toString(),
      'rate': rate,
      'amount': _rowAmountForRate(rate, count),
    };
  }

  int _pendingDigitCountForMode(String mode) {
    return selectedEntries.fold<int>(0, (total, row) {
      final len = row['number'].toString().trim().length;
      final matches = mode == '1'
          ? len == 1
          : mode == '2'
              ? len == 2
              : len >= 3;
      if (!matches) return total;
      return total + (int.tryParse(row['count'].toString()) ?? 0);
    });
  }

  double _savedAmountToday() {
    final businessDay =
        DrawScheduleStore.businessDateForDraw(selectedTime, at: _now);
    return BillsStore.todayAmountForUser(widget.username, businessDate: businessDay);
  }

  int _savedDigitCountToday(String mode) {
    final businessDay =
        DrawScheduleStore.businessDateForDraw(selectedTime, at: _now);
    return BillsStore.todayDigitCountForUser(
      widget.username,
      mode,
      businessDate: businessDay,
    );
  }

  int _effectiveDigitLimit(AppUser? user, String mode) {
    if (user != null && user.role != 'ADMIN') {
      final userLimit = DigitLimitStore.effectiveLimitForMode(
        selectedOption: mode,
        userDigit1: user.digit1CountLimit,
        userDigit2: user.digit2CountLimit,
        userDigit3: user.digit3CountLimit,
      );
      if (userLimit > 0) return userLimit;
    }
    return DigitLimitStore.limits.value.limitForMode(mode);
  }

  bool _validateUserLimits({required int addCount, required double addAmount}) {
    final user = UserStore.byUsername(widget.username);
    if (user == null || user.role == 'ADMIN') return true;

    final digitLimit = _effectiveDigitLimit(user, selectedOption);
    final modeTotal = _savedDigitCountToday(selectedOption) +
        _pendingDigitCountForMode(selectedOption) +
        addCount;
    if (digitLimit > 0 && modeTotal > digitLimit) {
      showErrorSnack(
        context,
        AppMsg.digitLimitExceeded(selectedOption, digitLimit, modeTotal),
      );
      return false;
    }

    if (user.amountLimit > 0) {
      final amountTotal =
          _savedAmountToday() + _totalAmount() + addAmount;
      if (amountTotal > user.amountLimit) {
        showErrorSnack(
          context,
          AppMsg.amountLimitExceeded(user.amountLimit, amountTotal),
        );
        return false;
      }
    }
    return true;
  }

  int _digitModeCountInBill(String mode) => _pendingDigitCountForMode(mode);

  bool _validateBillForSave() {
    if (!_drawBookingOpen) {
      _showDrawClosedMessage();
      return false;
    }
    final user = UserStore.byUsername(widget.username);

    if (user != null && user.isAgentRole) {
      if (!_schemeAllowsDraw(selectedTime)) {
        showErrorSnack(
          context,
          AppMsg.schemeDrawNotAllowed(user.scheme, selectedTime),
        );
        return false;
      }
    }

    if (user != null && user.role != 'ADMIN' && user.amountLimit > 0) {
      final amountTotal = _savedAmountToday() + _totalAmount();
      if (amountTotal > user.amountLimit) {
        showErrorSnack(
          context,
          AppMsg.amountLimitExceeded(user.amountLimit, amountTotal),
        );
        return false;
      }
    }

    for (final mode in ['3', '2', '1']) {
      final limit = _effectiveDigitLimit(user, mode);
      if (limit <= 0) continue;
      final modeTotal =
          _savedDigitCountToday(mode) + _digitModeCountInBill(mode);
      if (modeTotal > limit) {
        showErrorSnack(
          context,
          AppMsg.digitLimitExceeded(mode, limit, modeTotal),
        );
        return false;
      }
    }
    return true;
  }

  bool _schemeAllowsDraw(String drawTime) {
    final agent = UserStore.byUsername(widget.username);
    if (agent == null || !agent.isAgentRole) return true;
    if (agent.scheme == 'ALL') return true;
    return agent.scheme == drawTime;
  }

  int _totalCount() => selectedEntries.fold<int>(
      0, (total, row) => total + (int.tryParse(row["count"].toString()) ?? 0));

  double _totalAmount() => selectedEntries.fold<double>(
      0.0, (total, row) => total + BillRecord.readRowAmount(row["amount"]));

  double _commission() => 0.0;

  Color _timeColor(String time) => menuDrawColor(time);

  List<Color> _timeGradient(String time) => kAppBlueGradient;

  List<Color> _liveTimeLightGradient(String time) =>
      _drawLightGradientForTime(time);

  String _liveTimeText() {
    final int hour12 = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final String ampm = _now.hour >= 12 ? "PM" : "AM";
    return "$hour12:${_now.minute.toString().padLeft(2, "0")}:${_now.second.toString().padLeft(2, "0")} $ampm";
  }

  Widget _closeCountdownBadge() {
    final closeCountdown = DrawScheduleStore.bookingCloseCountdownText(
      selectedTime,
      at: _now,
    );
    final gradient = _liveTimeLightGradient(selectedTime);
    final borderColor = _timeColor(selectedTime).withValues(alpha: 0.35);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Container(
        height: _bookingToolbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: gradient.first,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: borderColor, width: 1),
        ),
        child: closeCountdown != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Text(
                    closeCountdown,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: Colors.red.shade800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              )
            : Center(
                child: Text(
                  _liveTimeText(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF263238),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _bookingDrawSelector() {
    final allowed = _allowedDrawsForUser(widget.username);
    final label = _shortDrawLabel(selectedTime);

    Widget chip() {
      return SizedBox(
        height: _bookingToolbarHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: kAppBlue,
            borderRadius: BorderRadius.zero,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  if (allowed.length > 1) ...[
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (allowed.length <= 1) return chip();

    return SizedBox(
      height: _bookingToolbarHeight,
      child: PopupMenuButton<String>(
      initialValue: selectedTime,
      padding: EdgeInsets.zero,
      onSelected: (draw) {
        setState(() => selectedTime = draw);
      },
      itemBuilder: (context) => [
        for (final draw in allowed)
          PopupMenuItem<String>(value: draw, child: Text(draw)),
      ],
      child: chip(),
      ),
    );
  }

  String _shortDrawLabel(String draw) {
    switch (draw.trim()) {
      case 'DEAR 1 PM':
        return 'D1';
      case 'LSK 3 PM':
        return 'L3';
      case 'DEAR 6 PM':
        return 'D6';
      case 'DEAR 8 PM':
        return 'D8';
      default:
        return draw;
    }
  }

  bool autoSubmit = false;

  bool _handleWhatsAppPaste(String text) {
    if (!_ensureCanSell()) return false;
    final result = parseWhatsAppFull(text);
    final List<Booking> bookings = result['bookings'];
    if (bookings.isEmpty) return false;

    setState(() {
      final name = result['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) customerNameController.text = name;
      final String code = _timeCode();
      for (final b in bookings) {
        String type;
        if (b.wordOrBoard != null) {
          final String w = b.wordOrBoard!.toUpperCase();
          if (["SUPER", "BOX", "A", "B", "C", "AB", "BC", "AC"].contains(w)) {
            type = "$code-$w";
          } else {
            type = "$code-$w";
          }
        } else {
          if (b.itemNumber.length == 3) {
            type = "$code-SUPER";
          } else if (b.itemNumber.length == 2) {
            type = "$code-AB";
          } else {
            type = "$code-A";
          }
        }

        final bool isSet = b.category == BookingCategory.permutation;

        for (final expanded
            in _expandImportedNumbers(b.itemNumber, forceSetExpand: isSet)) {
          selectedEntries.insert(0, _bookingRow(type, expanded, b.quantity));
        }
      }
    });

    if (mounted) {
      showSuccessSnack(context, AppMsg.entriesImported(bookings.length));
    }

    if (autoSubmit) {
      _saveCurrentBooking(skipConfirm: true);
    }
    return true;
  }

  String _formatConfirmAmount(double value) {
    if ((value - value.roundToDouble()).abs() < 0.001) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1);
  }

  Future<bool> _showSaveConfirmDialog() async {
    final nameResult = await showAppDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SaveConfirmDialog(
        initialName: customerNameController.text.trim(),
        totalCount: _totalCount(),
        totalAmount: _formatConfirmAmount(_totalAmount()),
      ),
    );
    if (nameResult == null) return false;
    customerNameController.text = nameResult;
    return true;
  }

  Future<void> _saveCurrentBooking({bool skipConfirm = false}) async {
    if (selectedEntries.isEmpty) return;
    if (!_ensureCanSell()) return;
    if (!_validateBillForSave()) return;

    if (!skipConfirm) {
      FocusScope.of(context).unfocus();
      final confirmed = await _showSaveConfirmDialog();
      if (!confirmed || !mounted) return;
    }

    final bookedAt = _now.toLocal();
    final businessDay =
        DrawScheduleStore.businessDateForDraw(selectedTime, at: bookedAt);

    for (final row in selectedEntries) {
      SalesStore.add(
        SaleEntry(
          type: row["type"] as String,
          number: row["number"] as String,
          count: int.tryParse(row["count"].toString()) ?? 0,
          amount: BillRecord.readRowAmount(row["amount"]),
          time: selectedTime,
          createdAt: bookedAt,
          businessDate: businessDay,
        ),
      );
    }

    final int billNo = 400000 + Random().nextInt(99999);
    final billRows =
        selectedEntries.map((e) => Map<String, dynamic>.from(e)).toList();
    BillsStore.add(
      BillRecord(
        billNo: billNo,
        createdAt: bookedAt,
        businessDate: businessDay,
        drawName: selectedTime,
        rows: billRows,
        username: widget.username,
        customerName: customerNameController.text.trim(),
      ),
    );

    FocusScope.of(context).unfocus();
    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: Colors.transparent,
              elevation: 8,
              borderRadius: BorderRadius.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    color: _bookingPageColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Text('😊', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppMsg.billSavedTitle,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 28,
                    ),
                    child: Text(
                      AppMsg.billNo(billNo),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _bookingPageColor,
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    color: _bookingPageColor,
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(
                            AppMsg.close,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            Navigator.push(
                              context,
                              appRoute(
                                EditBillPage(initialBillNo: billNo),
                              ),
                            );
                          },
                          child: Text(
                            AppMsg.viewBill,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    setState(() {
      selectedEntries.clear();
      numberController.clear();
      countController.clear();
      boxController.clear();
      customerNameController.clear();
    });
    FocusScope.of(context).requestFocus(numberFocusNode);
  }
}

class _SaveConfirmDialog extends StatefulWidget {
  final String initialName;
  final int totalCount;
  final String totalAmount;

  const _SaveConfirmDialog({
    required this.initialName,
    required this.totalCount,
    required this.totalAmount,
  });

  @override
  State<_SaveConfirmDialog> createState() => _SaveConfirmDialogState();
}

class _SaveConfirmDialogState extends State<_SaveConfirmDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: width - 48,
            margin: const EdgeInsets.only(top: 52),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                  child: Text(
                    AppMsg.confirmTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Color(0xFF212121),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppMsg.confirmSaveBill,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF424242),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        AppMsg.totalCount(widget.totalCount),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppMsg.totalAmount(widget.totalAmount),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _nameController,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        scrollPadding: EdgeInsets.zero,
                        style: const TextStyle(
                          color: Color(0xFF212121),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        cursorColor: const Color(0xFF1976D2),
                        decoration: InputDecoration(
                          labelText: AppMsg.billNote,
                          labelStyle: TextStyle(color: Colors.grey.shade700),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                          enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.grey.shade500),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: Color(0xFF1976D2),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          AppMsg.cancel,
                          style: const TextStyle(
                            color: Color(0xFF1976D2),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, _nameController.text.trim()),
                        child: Text(
                          AppMsg.ok,
                          style: const TextStyle(
                            color: Color(0xFF1976D2),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
