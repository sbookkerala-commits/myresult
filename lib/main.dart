import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/api_config.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'database/local_database.dart';
import 'whatsapp_booking_parser.dart';

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

DateTime _calendarDate(DateTime d) => DateTime(d.year, d.month, d.day);

String formatBillDateTime(DateTime dt) {
  final int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final String ampm = dt.hour >= 12 ? "PM" : "AM";
  final d = dt.day.toString().padLeft(2, "0");
  final m = dt.month.toString().padLeft(2, "0");
  final y = dt.year;
  return "$d/$m/$y $hour12:${dt.minute.toString().padLeft(2, "0")} $ampm";
}

/// Default report window: today (user can widen the range if needed).
DateTime defaultReportFromDate() => _calendarDate(DateTime.now());

DateTime defaultReportToDate() => _calendarDate(DateTime.now());

bool billInDateRange(DateTime billTime, DateTime from, DateTime to) {
  final b = _calendarDate(billTime);
  final f = _calendarDate(from);
  final t = _calendarDate(to);
  return !b.isBefore(f) && !b.isAfter(t);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.init();
  await SyncService.init();
  if (!kIsWeb) {
    await AppDatabase.ensureReady();
  }
  await UserStore.init();
  await BillsStore.init();
  await SalesStore.init();
  await ResultStore.init();
  unawaited(SyncService.flushQueue());
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(const MyApp());
}

class SaleEntry {
  final String type;
  final String number;
  final int count;
  final double amount;
  final String time;
  final DateTime createdAt;

  const SaleEntry({
    required this.type,
    required this.number,
    required this.count,
    required this.amount,
    required this.time,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        "type": type,
        "number": number,
        "count": count,
        "amount": amount,
        "time": time,
        "createdAt": createdAt.toIso8601String(),
      };

  static SaleEntry? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final created = DateTime.tryParse(json["createdAt"]?.toString() ?? "");
    if (created == null) return null;
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
      createdAt: created,
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

  const AppUser({
    required this.username,
    required this.password,
    required this.role,
    this.isBlocked = false,
  });

  Map<String, dynamic> toJson() => {
        "username": username,
        "password": password,
        "role": role,
        "isBlocked": isBlocked,
      };

  static AppUser? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final username = json["username"]?.toString() ?? "";
    final password = json["password"]?.toString() ?? "";
    final role = (json["role"]?.toString() ?? "").trim().toUpperCase();
    final isBlocked = json["isBlocked"] == true;
    if (username.trim().isEmpty || password.trim().isEmpty || role.isEmpty) {
      return null;
    }
    return AppUser(
      username: username.trim(),
      password: password.trim(),
      role: role,
      isBlocked: isBlocked,
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

  static Future<void> init() async {
    final String? raw = kIsWeb
        ? await LegacyPrefs.getString(_prefsKey)
        : await AppDatabase.loadUsersJson();

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final loaded = <AppUser>[];
          for (final item in decoded) {
            final u = AppUser.fromJson(Map<String, dynamic>.from(item));
            if (u != null) loaded.add(u);
          }
          users.value = loaded;
        }
      } catch (e) {
        debugPrint("Local users load error: $e");
      }
    }

    // Ensure admin exists
    if (!users.value.any((x) => x.role == "ADMIN")) {
      users.value = [
        ...users.value,
        const AppUser(username: "admin", password: "1234", role: "ADMIN")
      ];
    }
  }

  static void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(saveNow());
    });
  }

  static Future<void> saveNow() async {
    final payload = jsonEncode(users.value.map((u) => u.toJson()).toList());
    if (kIsWeb) {
      await LegacyPrefs.setString(_prefsKey, payload);
    } else {
      await AppDatabase.replaceUsers(
          users.value.map((u) => u.toJson()).toList());
    }
  }

  static void _syncUsersCloud() {
    if (AppSession.role == 'ADMIN') {
      unawaited(SyncService.queueUsers(
        users.value.map((u) => u.toJson()).toList(),
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

  static bool addUser({
    required String username,
    required String password,
    required String role,
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

    users.value = [
      ...users.value,
      AppUser(username: u, password: password.trim(), role: targetRole),
    ];
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
    next[idx] = AppUser(
        username: current.username, password: current.password, role: role);
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
    next[idx] =
        AppUser(username: current.username, password: pw, role: current.role);
    users.value = next;
    _scheduleSave();
    _syncUsersCloud();
    return true;
  }

  static bool toggleBlock(String username) {
    final idx = _indexOfUsername(username);
    if (idx < 0) return false;
    final current = users.value[idx];
    final next = List<AppUser>.from(users.value);
    next[idx] = AppUser(
      username: current.username,
      password: current.password,
      role: current.role,
      isBlocked: !current.isBlocked,
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
  final List<Map<String, dynamic>> rows;
  final String username;

  const BillRecord({
    required this.billNo,
    required this.createdAt,
    required this.rows,
    required this.username,
  });

  static void _normalizeRowMap(Map<String, dynamic> row) {
    final a = row["amount"];
    if (a is int) {
      row["amount"] = a.toDouble();
    } else if (a is num && a is! double) {
      row["amount"] = a.toDouble();
    }
  }

  Map<String, dynamic> toJson() => {
        "billNo": billNo,
        "createdAt": createdAt.toIso8601String(),
        "username": username,
        "rows": rows.map((r) => Map<String, dynamic>.from(r)).toList(),
      };

  static BillRecord? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final billRaw = json["billNo"];
    final int? billNo =
        billRaw is int ? billRaw : int.tryParse(billRaw.toString());
    final created = DateTime.tryParse(json["createdAt"]?.toString() ?? "");
    final username = json["username"]?.toString() ?? "";
    if (billNo == null || created == null) return null;

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
    return BillRecord(
        billNo: billNo, createdAt: created, rows: rows, username: username);
  }

  int get totalCount => rows.fold<int>(
        0,
        (total, row) => total + (int.tryParse(row["count"].toString()) ?? 0),
      );

  double get totalAmount => rows.fold<double>(
        0.0,
        (total, row) => total + ((row["amount"] as double?) ?? 0.0),
      );
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
    bills.value = localBills;
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
    _scheduleSave();
    unawaited(SyncService.queueBooking(r.toJson()));
  }

  static BillRecord? byBillNo(int no) {
    try {
      return bills.value.firstWhere((b) => b.billNo == no);
    } catch (_) {
      return null;
    }
  }

  static void delete(int no) {
    bills.value = bills.value.where((b) => b.billNo != no).toList();
    _scheduleSave();
    unawaited(SyncService.queueBookingDelete(no));
  }

  static void notifyUpdated([BillRecord? bill]) {
    bills.value = [...bills.value];
    _scheduleSave();
    if (bill != null) {
      unawaited(SyncService.queueBooking(bill.toJson()));
    }
  }
}

class ResultSnapshot {
  final String drawCode;
  final DateTime date;
  final List<String> prizes; // 5
  final List<String> compliments; // 30

  const ResultSnapshot({
    required this.drawCode,
    required this.date,
    required this.prizes,
    required this.compliments,
  });

  Map<String, dynamic> toJson() => {
        "drawCode": drawCode,
        "date": DateTime(date.year, date.month, date.day).toIso8601String(),
        "prizes": prizes,
        "compliments": compliments,
      };

  static ResultSnapshot? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final parsed = DateTime.tryParse(json["date"]?.toString() ?? "");
    if (parsed == null) return null;
    final pRaw = json["prizes"];
    final cRaw = json["compliments"];
    if (pRaw is! List || cRaw is! List) return null;
    return ResultSnapshot(
      drawCode: json["drawCode"]?.toString() ?? "",
      date: parsed,
      prizes: pRaw.map((e) => e.toString()).toList(),
      compliments: cRaw.map((e) => e.toString()).toList(),
    );
  }
}

class ResultStore {
  static const String _prefsKey = "app_results_v1";

  static final ValueNotifier<Map<String, ResultSnapshot>> results =
      ValueNotifier<Map<String, ResultSnapshot>>({});

  static Timer? _saveDebounce;

  static String _key(String drawCode, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return "$drawCode-${d.year}-${d.month}-${d.day}";
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
    final map = {...results.value};
    map[_key(snapshot.drawCode, snapshot.date)] = snapshot;
    results.value = map;
    _scheduleSave();
    unawaited(SyncService.queueResult(snapshot.toJson()));
  }
}

/// Merge cloud restore payload into local stores (after login).
Future<void> applyCloudRestore(Map<String, dynamic> data) async {
  final bookings = data['bookings'];
  if (bookings is List && bookings.isNotEmpty) {
    final loaded = <BillRecord>[];
    for (final item in bookings) {
      final b = BillRecord.fromJson(Map<String, dynamic>.from(item as Map));
      if (b != null) loaded.add(b);
    }
    if (loaded.isNotEmpty) {
      BillsStore.bills.value = loaded;
      await BillsStore.saveNow();
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
        final k = '${s.drawCode}-${d.year}-${d.month}-${d.day}';
        map[k] = s;
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

double _calculateWinningPrize(
    Map<String, dynamic> row, ResultSnapshot snapshot) {
  final String typeFull = row["type"].toString().toUpperCase();
  final String number = _digitsOnly(row["number"].toString());
  final int count = int.tryParse(row["count"].toString()) ?? 0;
  if (count <= 0 || number.isEmpty) return 0.0;

  final type = typeFull.split("-").last;
  final prizes = snapshot.prizes.map(_digitsOnly).toList();
  final compliments = snapshot.compliments.map(_digitsOnly).toList();

  if (prizes.isEmpty) return 0.0;
  final first = prizes[0];
  if (first.length < 3) return 0.0;

  double unitPrize = 0.0;
  bool isBox = type == "BOX";

  if (type == "A") {
    if (number == first[0]) unitPrize = 100.0;
  } else if (type == "B") {
    if (number.isNotEmpty && number[0] == first[1]) unitPrize = 100.0;
  } else if (type == "C") {
    if (number.isNotEmpty && number[0] == first[2]) unitPrize = 100.0;
  } else if (type == "AB") {
    if (number == first.substring(0, 2)) unitPrize = 700.0;
  } else if (type == "BC") {
    if (number == first.substring(1, 3)) unitPrize = 700.0;
  } else if (type == "AC") {
    if (number == (first[0] + first[2])) unitPrize = 700.0;
  } else if (type == "SUPER" || type == "BOX") {
    if (number == prizes[0]) {
      unitPrize = isBox ? 3000.0 : 5000.0;
    } else if (prizes.length > 1 && number == prizes[1]) {
      unitPrize = isBox ? 800.0 : 500.0;
    } else if (prizes.length > 2 && number == prizes[2]) {
      unitPrize = isBox ? 800.0 : 250.0;
    } else if (prizes.length > 3 && number == prizes[3]) {
      unitPrize = isBox ? 800.0 : 100.0;
    } else if (prizes.length > 4 && number == prizes[4]) {
      unitPrize = isBox ? 800.0 : 50.0;
    } else if (!isBox && compliments.contains(number)) {
      unitPrize = 20.0;
    }
  }

  return unitPrize * count;
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
  final snapshot = ResultStore.get(drawCode, _calendarDate(bill.createdAt));
  if (snapshot == null) return [];

  final rows = <Map<String, dynamic>>[];
  for (final row in bill.rows) {
    final prize = _calculateWinningPrize(row, snapshot);
    if (prize > 0) {
      final winningRow = Map<String, dynamic>.from(row);
      winningRow["winningPrize"] = prize;
      rows.add(winningRow);
    }
  }
  return rows;
}

/// Smooth lift-and-fade page transition with subtle depth when stacked.
Route<T> appRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 290),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final enter = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return AnimatedBuilder(
        animation: Listenable.merge([animation, secondaryAnimation]),
        builder: (context, _) {
          final t = enter.value;
          final depth = secondaryAnimation.value * animation.value;
          final scale =
              (0.975 + 0.025 * t) * (1.0 - 0.045 * depth);
          final dy = 28.0 * (1.0 - t);
          final dx = 12.0 * (1.0 - t);
          final opacity = t.clamp(0.0, 1.0);

          return FadeTransition(
            opacity: AlwaysStoppedAnimation(opacity),
            child: Transform.translate(
              offset: Offset(dx, dy),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    child,
                    if (depth > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: const Color(0xFF004D40)
                                .withValues(alpha: 0.1 * depth),
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.white,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String username = "";
  String password = "";
  String message = "";
  bool _loading = false;

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
          message = "Your account is blocked. Please contact admin.";
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
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text("Restoring data from cloud...")),
              ],
            ),
          ),
        ),
      );

      try {
        final data = await SyncService.restoreFromCloud();
        await applyCloudRestore(data);
        await SyncService.flushQueue();
      } catch (e) {
        debugPrint('Cloud restore skipped: $e');
      }

      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      Navigator.push(
        context,
        appRoute(HomePage(username: uname)),
      );
    } on ApiException {
      final user = UserStore.authenticate(username, password);
      if (user != null) {
        if (user.isBlocked) {
          setState(() {
            message = "Your account is blocked. Please contact admin.";
            _loading = false;
          });
          return;
        }
        AppSession.username = user.username;
        AppSession.role = user.role;
        if (!mounted) return;
        Navigator.push(
          context,
          appRoute(HomePage(username: user.username)),
        );
      } else {
        setState(() {
          message = "Wrong Username or Password";
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        message = "Login failed: $e";
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
      backgroundColor: Colors.orange[300],
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 40),
                child: Center(
                  child: Container(
                    width: 420,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_month,
                            size: 80, color: Colors.blue),
                        const SizedBox(height: 20),
                        TextField(
                          onChanged: (value) => username = value,
                          decoration:
                              const InputDecoration(hintText: "User Name"),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          obscureText: true,
                          onChanged: (value) => password = value,
                          decoration:
                              const InputDecoration(hintText: "Password"),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.all(15),
                            ),
                            onPressed: _loading ? null : _doLogin,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Login"),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(message,
                            style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final String username;
  const HomePage({super.key, required this.username});

  void _openDrawPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select draw',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ticketButton(ctx, "DEAR 1 PM", const Color(0xFF1565C0), username),
            ticketButton(ctx, "LSK 3 PM", const Color(0xFF2E7D32), username),
            ticketButton(ctx, "DEAR 6 PM", const Color(0xFF6A1B9A), username),
            ticketButton(ctx, "DEAR 8 PM", const Color(0xFFAD1457), username),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.role == "ADMIN";
    return Scaffold(
      body: Container(
        decoration: _reportPageBgDecoration(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _reportAppBar(username, context),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
          _simpleMenuTile(
            context,
            icon: Icons.add_circle_outline,
            title: 'Add Ticket',
            onTap: () => _openDrawPicker(context),
          ),
          _simpleMenuTile(
            context,
            icon: Icons.bar_chart_outlined,
            title: 'Reports',
            onTap: () => Navigator.push(
              context,
              appRoute(const ReportsPage()),
            ),
          ),
          _simpleMenuTile(
            context,
            icon: Icons.emoji_events_outlined,
            title: 'Results',
            onTap: () => Navigator.push(
              context,
              appRoute(const DearResultPage()),
            ),
          ),
          _simpleMenuTile(
            context,
            icon: Icons.list_alt_outlined,
            title: 'Price List',
            onTap: () => Navigator.push(
              context,
              appRoute(const PriceListPage()),
            ),
          ),
          _simpleMenuTile(
            context,
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
              icon: Icons.people_outline,
              title: 'Manage Users',
              onTap: () => Navigator.push(
                context,
                appRoute(const ManageUsersPage()),
              ),
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
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _appGradient.first.withValues(alpha: 0.85),
                    _appGradient.last,
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            title: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ),
        ),
      ),
    ),
  );
}

const Color _reportBg = Color(0xFFF4F8F7);
const Color _appPrimary = Color(0xFF00796B);
const List<Color> _appGradient = [Color(0xFF00897B), Color(0xFF004D40)];

// Kept for prize accents in winning cards
const Color _salesAccent = _appPrimary;

BoxDecoration _appGradientBox({BorderRadius? radius}) {
  return BoxDecoration(
    gradient: const LinearGradient(
      colors: _appGradient,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: radius ?? BorderRadius.circular(8),
  );
}

Decoration _reportPageBgDecoration() {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        _appGradient.first.withValues(alpha: 0.14),
        _reportBg,
        Colors.white,
      ],
    ),
  );
}

Widget _reportFormCard(Widget child) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _appGradient.first.withValues(alpha: 0.15)),
      boxShadow: [
        BoxShadow(
          color: _appGradient.last.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: child,
  );
}

Widget _appGradientButton({
  required VoidCallback? onPressed,
  required Widget child,
}) {
  return DecoratedBox(
    decoration: _appGradientBox(radius: BorderRadius.circular(8)),
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      child: child,
    ),
  );
}

AppBar _reportAppBar(String title, BuildContext context) {
  return AppBar(
    title: Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 17,
      ),
    ),
    backgroundColor: _appGradient.first,
    foregroundColor: Colors.white,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    flexibleSpace: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: _appGradient,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    actions: [
      IconButton(
        onPressed: () => goToMainHome(context),
        icon: const Icon(Icons.home_outlined, color: Colors.white),
        tooltip: 'Home',
      ),
    ],
  );
}

Color _salesDrawColor(String code) {
  switch (code) {
    case "DEAR1":
      return const Color(0xFF1565C0);
    case "LSK3":
      return const Color(0xFF2E7D32);
    case "DEAR6":
      return const Color(0xFF6A1B9A);
    case "DEAR8":
      return const Color(0xFFAD1457);
    default:
      return const Color(0xFF546E7A);
  }
}

Color _salesDrawTint(String code) =>
    _salesDrawColor(code).withValues(alpha: 0.12);

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

Widget _salesDrawBar({
  required String selected,
  required ValueChanged<String> onChanged,
}) {
  const options = ["ALL", "DEAR1", "LSK3", "DEAR6", "DEAR8"];
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          _appGradient.first.withValues(alpha: 0.12),
          _appGradient.last.withValues(alpha: 0.08),
        ],
      ),
      borderRadius: BorderRadius.circular(10),
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
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  gradient: sel
                      ? LinearGradient(
                          colors: [c, c.withValues(alpha: 0.75)],
                        )
                      : null,
                  color: sel ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                            color: c.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
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

InputDecoration _salesFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
    filled: true,
    fillColor: const Color(0xFFF5F7FA),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

Widget _salesStatChip(String label, String value, Color bg) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bg, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _appGradient.first.withValues(alpha: 0.12)),
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

InputDecoration _winningGroupDecoration() => _salesFieldDecoration("Group");

InputDecoration _winningModeDecoration() => _salesFieldDecoration("Mode");

Widget _reportDateBox(
  BuildContext context, {
  required String label,
  required DateTime value,
  required ValueChanged<DateTime> onChanged,
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
      decoration: _salesFieldDecoration(label),
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
}) {
  return Scaffold(
    body: Container(
      decoration: _reportPageBgDecoration(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _reportAppBar(title, context),
        body: body,
      ),
    ),
  );
}

const List<DropdownMenuItem<String>> _winningGroupItems = [
  DropdownMenuItem(value: "Select", child: Text("All")),
  DropdownMenuItem(value: "A", child: Text("A")),
  DropdownMenuItem(value: "B", child: Text("B")),
  DropdownMenuItem(value: "C", child: Text("C")),
  DropdownMenuItem(value: "AB", child: Text("AB")),
  DropdownMenuItem(value: "BC", child: Text("BC")),
  DropdownMenuItem(value: "AC", child: Text("AC")),
  DropdownMenuItem(value: "SUPER", child: Text("SUPER")),
  DropdownMenuItem(value: "BOX", child: Text("BOX")),
];

const List<DropdownMenuItem<String>> _winningModeItems = [
  DropdownMenuItem(value: "Select", child: Text("All")),
  DropdownMenuItem(value: "1", child: Text("1 digit")),
  DropdownMenuItem(value: "2", child: Text("2 digit")),
  DropdownMenuItem(value: "3", child: Text("3 digit")),
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

class ManageUsersPage extends StatefulWidget {
  const ManageUsersPage({super.key});

  @override
  State<ManageUsersPage> createState() => _ManageUsersPageState();
}

class _ManageUsersPageState extends State<ManageUsersPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String role = "AGENT";

  Future<void> _promptChangeRole(AppUser user) async {
    String nextRole = user.role;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("Change role: ${user.username}"),
              content: DropdownButtonFormField<String>(
                key: ValueKey(nextRole),
                initialValue: nextRole,
                decoration: const InputDecoration(
                  labelText: "Role",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: "ADMIN", child: Text("ADMIN")),
                  DropdownMenuItem(value: "AGENT", child: Text("AGENT")),
                  DropdownMenuItem(value: "SUBAGENT", child: Text("SUB AGENT")),
                  DropdownMenuItem(value: "CUSTOMER", child: Text("CUSTOMER")),
                ],
                onChanged: (v) =>
                    setDialogState(() => nextRole = v ?? nextRole),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel")),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Save")),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final changed =
        UserStore.updateRole(username: user.username, newRole: nextRole);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed
              ? "Role updated"
              : "Failed: can't remove last ADMIN, can't demote yourself, or invalid role",
        ),
      ),
    );
  }

  Future<void> _confirmDelete(AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Delete user?"),
          content: Text("Delete ${user.username}? This cannot be undone."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final deleted = UserStore.deleteUser(user.username);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? "User deleted"
              : "Failed: can't delete yourself, can't delete last ADMIN, or user missing",
        ),
      ),
    );
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _reportPage(
      context: context,
      title: "Manage Users",
      body: ValueListenableBuilder<List<AppUser>>(
        valueListenable: UserStore.users,
        builder: (context, users, _) {
          final active = users.where((u) => !u.isBlocked).length;
          final blocked = users.length - active;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      _usersStatChip("Total", "${users.length}"),
                      const SizedBox(width: 8),
                      _usersStatChip("Active", "$active"),
                      const SizedBox(width: 8),
                      _usersStatChip("Blocked", "$blocked"),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _reportFormCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _appGradient.first.withValues(alpha: 0.85),
                                  _appGradient.last,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.person_add_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "Create User",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: usernameController,
                        decoration: _salesFieldDecoration("Username"),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: _salesFieldDecoration("Password"),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        key: ValueKey(role),
                        initialValue: role,
                        decoration: _salesFieldDecoration("Role"),
                        items: const [
                          DropdownMenuItem(
                              value: "AGENT", child: Text("Agent")),
                          DropdownMenuItem(
                              value: "SUBAGENT", child: Text("Sub Agent")),
                          DropdownMenuItem(
                              value: "CUSTOMER", child: Text("Customer")),
                        ],
                        onChanged: (v) => setState(() => role = v ?? "AGENT"),
                      ),
                      const SizedBox(height: 14),
                      _appGradientButton(
                        onPressed: () {
                          final ok = UserStore.addUser(
                            username: usernameController.text,
                            password: passwordController.text,
                            role: role,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? "User created successfully"
                                    : "Failed: check duplicate/empty fields",
                              ),
                            ),
                          );
                          if (ok) {
                            usernameController.clear();
                            passwordController.clear();
                            setState(() => role = "AGENT");
                          }
                        },
                        child: const Text("Create User"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    "Account List (${users.length})",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (users.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.people_outline,
                            size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text(
                          "No users yet",
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                else
                  ...users.map((u) => _userCard(u)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _usersStatChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _appGradient.first.withValues(alpha: 0.12),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _appGradient.first.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toUpperCase()) {
      case "ADMIN":
        return _appGradient.first;
      case "AGENT":
        return const Color(0xFF1565C0);
      case "SUBAGENT":
        return const Color(0xFF6A1B9A);
      case "CUSTOMER":
        return const Color(0xFF546E7A);
      default:
        return Colors.grey;
    }
  }

  String _roleLabel(String role) {
    switch (role.toUpperCase()) {
      case "SUBAGENT":
        return "Sub Agent";
      default:
        return role[0] + role.substring(1).toLowerCase();
    }
  }

  Widget _userCard(AppUser u) {
    final isSelf = u.username.trim().toLowerCase() ==
        AppSession.username.trim().toLowerCase();
    final roleColor = _roleColor(u.role);
    final bg = roleColor.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: u.isBlocked ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: u.isBlocked ? Colors.red.shade50 : bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: u.isBlocked
                          ? [Colors.red.shade300, Colors.red.shade600]
                          : [roleColor, roleColor.withValues(alpha: 0.75)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    u.isBlocked ? Icons.block : Icons.person_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              u.username,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelf) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _appGradient.first.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "You",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _appGradient.last,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _roleLabel(u.role),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: roleColor,
                              ),
                            ),
                          ),
                          if (u.isBlocked) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "Blocked",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isSelf)
                  IconButton(
                    icon: Icon(
                      u.isBlocked ? Icons.lock_open_outlined : Icons.block,
                      color: u.isBlocked ? Colors.green.shade600 : Colors.orange.shade700,
                      size: 22,
                    ),
                    tooltip: u.isBlocked ? "Unblock" : "Block",
                    onPressed: () =>
                        setState(() => UserStore.toggleBlock(u.username)),
                  ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                  onSelected: (v) async {
                    if (v == "password") await _promptResetPassword(u);
                    if (v == "role") await _promptChangeRole(u);
                    if (v == "delete" && !isSelf) await _confirmDelete(u);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: "password",
                      child: Text("Reset Password"),
                    ),
                    const PopupMenuItem(
                      value: "role",
                      child: Text("Change Role"),
                    ),
                    if (!isSelf)
                      const PopupMenuItem(
                        value: "delete",
                        child: Text(
                          "Delete Account",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptResetPassword(AppUser u) async {
    final TextEditingController pc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Reset Password: ${u.username}"),
        content: TextField(
          controller: pc,
          decoration: const InputDecoration(labelText: "New Password"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Reset"),
          ),
        ],
      ),
    );

    if (ok == true && pc.text.trim().isNotEmpty) {
      final changed = UserStore.setPassword(
          username: u.username, newPassword: pc.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                changed ? "Password updated" : "Failed to update password")));
        setState(() {});
      }
    }
    pc.dispose();
  }
}

class PriceListPage extends StatefulWidget {
  const PriceListPage({super.key});

  @override
  State<PriceListPage> createState() => _PriceListPageState();
}

class _PriceListPageState extends State<PriceListPage> {
  String _selectedDraw = "DEAR 1 PM";

  static const List<String> _draws = [
    "DEAR 1 PM",
    "LSK 3 PM",
    "DEAR 6 PM",
    "DEAR 8 PM",
  ];

  static const List<Map<String, dynamic>> _dear1Schemes = [
    {
      "name": "DEAR1-SUPER",
      "group": "Group 3",
      "rate": 10,
      "rows": [
        [1, 1, 5000, 0],
        [2, 1, 500, 0],
        [3, 1, 250, 0],
        [4, 1, 100, 0],
        [5, 1, 50, 0],
        [6, 30, 20, 0],
      ],
    },
    {
      "name": "DEAR1-BOX",
      "group": "Group 3",
      "rate": 10,
      "rows": [
        [1, 1, 3000, 0],
        [2, 1, 800, 0],
        [3, 1, 800, 0],
        [4, 1, 800, 0],
        [5, 1, 800, 0],
        [6, 1, 800, 0],
      ],
    },
    {
      "name": "DEAR1-A",
      "group": "Group 1",
      "rate": 12,
      "rows": [
        [1, 1, 100, 0],
      ],
    },
    {
      "name": "DEAR1-B",
      "group": "Group 1",
      "rate": 12,
      "rows": [
        [1, 1, 100, 0],
      ],
    },
    {
      "name": "DEAR1-C",
      "group": "Group 1",
      "rate": 12,
      "rows": [
        [1, 1, 100, 0],
      ],
    },
    {
      "name": "DEAR1-AB",
      "group": "Group 2",
      "rate": 10,
      "rows": [
        [1, 1, 700, 0],
      ],
    },
    {
      "name": "DEAR1-BC",
      "group": "Group 2",
      "rate": 10,
      "rows": [
        [1, 1, 700, 0],
      ],
    },
    {
      "name": "DEAR1-AC",
      "group": "Group 2",
      "rate": 10,
      "rows": [
        [1, 1, 700, 0],
      ],
    },
  ];

  List<Map<String, dynamic>> get _activeSchemes {
    if (_selectedDraw == "DEAR 1 PM") return _dear1Schemes;
    return _dear1Schemes
        .map((s) => {
              ...s,
              "name": s["name"].toString().replaceFirst("DEAR1", _drawPrefix()),
            })
        .toList();
  }

  String _drawPrefix() {
    switch (_selectedDraw) {
      case "LSK 3 PM":
        return "LSK3";
      case "DEAR 6 PM":
        return "DEAR6";
      case "DEAR 8 PM":
        return "DEAR8";
      default:
        return "DEAR1";
    }
  }

  Color _drawColor(String draw) {
    switch (draw) {
      case "LSK 3 PM":
        return const Color(0xFF2E7D32);
      case "DEAR 6 PM":
        return const Color(0xFF6A1B9A);
      case "DEAR 8 PM":
        return const Color(0xFFAD1457);
      default:
        return const Color(0xFF1565C0);
    }
  }

  String _drawShort(String draw) => draw.replaceAll(" PM", "");

  Color _schemeTint(String name) {
    final n = name.toUpperCase();
    if (n.contains("SUPER")) return const Color(0xFF5E35B1);
    if (n.contains("BOX")) return const Color(0xFF00897B);
    if (n.contains("-AB") || n.contains("-BC") || n.contains("-AC")) {
      return const Color(0xFF3949AB);
    }
    return const Color(0xFFE65100);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _drawColor(_selectedDraw);

    final byGroup = <String, List<Map<String, dynamic>>>{};
    for (final s in _activeSchemes) {
      final g = s["group"]?.toString() ?? "Other";
      byGroup.putIfAbsent(g, () => []).add(s);
    }
    const groupOrder = ["Group 3", "Group 2", "Group 1"];

    return _reportPage(
      context: context,
      title: 'Price List',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        children: [
          _lightDrawBar(accent),
          const SizedBox(height: 12),
          for (final group in groupOrder)
            if (byGroup[group] != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 2),
                child: Text(
                  group,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              ...byGroup[group]!.map(_schemeCard),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _lightDrawBar(Color accent) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: _draws.map((d) {
          final sel = d == _selectedDraw;
          final c = _drawColor(d);
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedDraw = d),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    _drawShort(d),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: sel ? c : Colors.grey.shade600,
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

  Widget _schemeCard(Map<String, dynamic> scheme) {
    final name = scheme["name"].toString();
    final tint = _schemeTint(name);
    final List<List<int>> rows = (scheme["rows"] as List)
        .map<List<int>>((r) => (r as List).map((e) => e as int).toList())
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        scheme["group"].toString(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Rate ${scheme["rate"]}',
                    style: TextStyle(
                      color: tint,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: _prizeTable(rows, tint),
          ),
        ],
      ),
    );
  }

  Widget _prizeTable(List<List<int>> rows, Color accent) {
    return Column(
      children: [
        _prizeRow(
          const ["Position", "Count", "Amount", "Super"],
          accent: accent,
          header: true,
        ),
        for (var i = 0; i < rows.length; i++)
          _prizeRow(
            [
              rows[i][0].toString(),
              rows[i][1].toString(),
              rows[i][2].toString(),
              rows[i][3].toString(),
            ],
            accent: accent,
            header: false,
            zebra: i.isOdd,
          ),
      ],
    );
  }

  Widget _prizeRow(
    List<String> cells, {
    required Color accent,
    required bool header,
    bool zebra = false,
  }) {
    return Container(
      color: header
          ? const Color(0xFFF5F6F8)
          : (zebra ? const Color(0xFFFAFBFC) : Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        children: List.generate(4, (i) {
          return Expanded(
            child: Text(
              cells[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: header ? 11 : 14,
                fontWeight: header ? FontWeight.w600 : FontWeight.w400,
                color: header ? Colors.grey.shade700 : Colors.black87,
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Lottery-style result screen (reference layout: draw, prize rows, compliments grid).
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
  DateTime _resultDate = DateTime.now();

  /// Prize values — replace with API later; default **---** when no data.
  final List<String> _prizeValues = List<String>.filled(5, "---");

  /// Compliment cells (3×10) — default **---** when no data.
  final List<String> _complimentValues = List<String>.filled(30, "---");

  /// Matches reference labels: `DEAR 1 PM` → `DEAR 1PM`.
  String _drawDisplayTitle(String draw) => draw.replaceAll(" PM", "PM");

  Color _drawThemeColor(String draw) {
    switch (draw) {
      case "DEAR 1 PM":
        return const Color(0xFF1565C0);
      case "LSK 3 PM":
        return const Color(0xFF2E7D32);
      case "DEAR 6 PM":
        return const Color(0xFF6A1B9A);
      case "DEAR 8 PM":
        return const Color(0xFFAD1457);
      default:
        return _defaultBlue;
    }
  }

  List<Color> _drawThemeGradient(String draw) {
    switch (draw) {
      case "DEAR 1 PM":
        return const [Color(0xFF1565C0), Color(0xFF0D47A1)];
      case "LSK 3 PM":
        return const [Color(0xFF2E7D32), Color(0xFF1B5E20)];
      case "DEAR 6 PM":
        return const [Color(0xFF6A1B9A), Color(0xFF4A148C)];
      case "DEAR 8 PM":
        return const [Color(0xFFAD1457), Color(0xFF880E4F)];
      default:
        return const [Color(0xFF1A237E), Color(0xFF0D1B66)];
    }
  }

  String _dateLine() {
    final d = _resultDate;
    return "${d.day.toString().padLeft(2, "0")}-${d.month.toString().padLeft(2, "0")}-${d.year}";
  }

  String _currentDrawCode() => _drawCodeFromFilter(_selectedDraw);

  void _loadSavedResult() {
    final snapshot = ResultStore.get(_currentDrawCode(), _resultDate);
    if (snapshot == null) {
      setState(() {
        for (int i = 0; i < _prizeValues.length; i++) {
          _prizeValues[i] = "---";
        }
        for (int i = 0; i < _complimentValues.length; i++) {
          _complimentValues[i] = "---";
        }
      });
      return;
    }
    setState(() {
      for (int i = 0; i < 5; i++) {
        _prizeValues[i] =
            i < snapshot.prizes.length ? snapshot.prizes[i] : "---";
      }
      for (int i = 0; i < 30; i++) {
        _complimentValues[i] =
            i < snapshot.compliments.length ? snapshot.compliments[i] : "---";
      }
    });
  }

  void _showEditResultDialog() {
    final pControllers = List.generate(
      5,
      (i) => TextEditingController(
          text: _prizeValues[i] == "---" ? "" : _prizeValues[i]),
    );
    final compController = TextEditingController(
      text: _complimentValues.where((v) => v != "---").join(" "),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Update Result: ${_drawDisplayTitle(_selectedDraw)}"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(
                  5,
                  (i) => TextField(
                    controller: pControllers[i],
                    decoration: InputDecoration(labelText: "${i + 1}st Prize"),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: compController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: "Compliments (Paste all 30 numbers)",
                    hintText: "Separate by space, comma, or newline",
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL")),
          ElevatedButton(
            onPressed: () {
              final List<String> p = pControllers
                  .map((c) => c.text.trim().isEmpty ? "---" : c.text.trim())
                  .toList();
              final rawComp =
                  compController.text.replaceAll(RegExp(r'[,\n\r]'), ' ');
              final List<String> c = rawComp
                  .split(RegExp(r'\s+'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();

              final List<String> finalComp =
                  List.generate(30, (i) => i < c.length ? c[i] : "---");

              ResultStore.save(ResultSnapshot(
                drawCode: _currentDrawCode(),
                date: _resultDate,
                prizes: p,
                compliments: finalComp,
              ));

              Navigator.pop(context);
              _loadSavedResult();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Result updated successfully")),
              );
            },
            child: const Text("SAVE"),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSavedResult();
    ResultStore.results.addListener(_loadSavedResult);
    SyncService.restoring.addListener(_onRestoreChanged);
  }

  @override
  void dispose() {
    ResultStore.results.removeListener(_loadSavedResult);
    SyncService.restoring.removeListener(_onRestoreChanged);
    super.dispose();
  }

  void _onRestoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Color themeColor = _drawThemeColor(_selectedDraw);
    final List<Color> themeGradient = _drawThemeGradient(_selectedDraw);
    final bool loading = SyncService.restoring.value;
    return Stack(
      children: [
        Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: themeGradient.first,
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: themeGradient.first,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: themeGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: PopupMenuButton<String>(
          offset: const Offset(0, kToolbarHeight * 0.9),
          color: Colors.white,
          onSelected: (v) {
            setState(() => _selectedDraw = v);
            _loadSavedResult();
          },
          itemBuilder: (context) => _draws
              .map((d) => PopupMenuItem<String>(value: d, child: Text(d)))
              .toList(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _drawDisplayTitle(_selectedDraw),
                    maxLines: 1,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.white),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          if (AppSession.role == "ADMIN")
            IconButton(
              onPressed: _showEditResultDialog,
              icon: const Icon(Icons.edit_note),
              tooltip: "Update Result",
            )
          else
            IconButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Result update only in Admin app"),
                  ),
                );
              },
              icon: const Icon(Icons.lock_outline),
              tooltip: "Admin only",
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text("SHARE"),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 4, 15, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dateLine(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        "${_drawDisplayTitle(_selectedDraw)} RESULT",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: themeColor,
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _resultDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _resultDate = picked);
                        _loadSavedResult();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: themeColor,
                      backgroundColor: Colors.white,
                      side: BorderSide(
                          color: themeGradient.last.withValues(alpha: 0.45),
                          width: 1),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon:
                        Icon(Icons.calendar_month, color: themeColor, size: 14),
                    label: const Text("HISTORY",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, inner) {
                    const double complimentsH = 18;
                    const double gapLabel = 4;
                    const double prizeFraction = 0.40;
                    const int gridCols = 3;
                    const int gridRows = 10;
                    const double mainG = 3;
                    const double crossG = 6;
                    const double complimentsHorizontalInset = 12;

                    final double avail =
                        inner.maxHeight - complimentsH - gapLabel * 2;
                    final double prizeH =
                        (avail * prizeFraction).clamp(0.0, double.infinity);
                    final double gridH =
                        (avail - prizeH).clamp(0.0, double.infinity);
                    final double gridW =
                        (inner.maxWidth - 2 * complimentsHorizontalInset)
                            .clamp(0.0, double.infinity);

                    final double cellW =
                        (gridW - (gridCols - 1) * crossG) / gridCols;
                    final double cellH =
                        (gridH - (gridRows - 1) * mainG) / gridRows;
                    final double aspectRatio =
                        (cellW > 0 && cellH > 0) ? (cellW / cellH) : 3.8;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: prizeH,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: _prizeRow("1st Prize",
                                    const Color(0xFFC8E6C9), _prizeValues[0]),
                              ),
                              Expanded(
                                child: _prizeRow("2nd Prize",
                                    const Color(0xFFBBDEFB), _prizeValues[1]),
                              ),
                              Expanded(
                                child: _prizeRow("3rd Prize",
                                    const Color(0xFFFFF9C4), _prizeValues[2]),
                              ),
                              Expanded(
                                child: _prizeRow("4th Prize",
                                    const Color(0xFFE1BEE7), _prizeValues[3]),
                              ),
                              Expanded(
                                child: _prizeRow("5th Prize",
                                    const Color(0xFFFFE0B2), _prizeValues[4]),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: gapLabel),
                        Text(
                          "COMPLIMENTS",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: gapLabel),
                        Center(
                          child: SizedBox(
                            width: gridW,
                            height: gridH,
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: gridCols,
                                mainAxisSpacing: mainG,
                                crossAxisSpacing: crossG,
                                childAspectRatio: aspectRatio,
                              ),
                              itemCount: 30,
                              itemBuilder: (context, index) {
                                return Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                  ),
                                  alignment: Alignment.center,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _complimentValues[index],
                                      style: TextStyle(
                                        fontSize: cellH > 0
                                            ? (cellH * 0.42).clamp(10.0, 14.0)
                                            : 14,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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

  Widget _prizeRow(String label, Color bg, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: Color(0xFF1A1A1A),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget ticketButton(
    BuildContext context, String text, Color color, String username) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          appRoute(
            TicketPage(title: text, username: username),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _reportPageBgDecoration(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: _reportAppBar("Reports", context),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
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
  String modeFilter = "Select";
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
      if (!_inRange(bill.createdAt)) return false;
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
      final winningRows =
          _winningRowsForBill(bill, drawFilter: drawFilter);
      return winningRows.isNotEmpty;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tint = _salesDrawTint(drawFilter);

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
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: ticketNumberController,
                        keyboardType: TextInputType.number,
                        decoration:
                            _salesFieldDecoration("Ticket Number (optional)"),
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
                        child: const Text("View Bills"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    drawFilter == "ALL"
                        ? "All draws · winning tickets only"
                        : "${_salesDrawLabel(drawFilter)} · winning tickets",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: _salesDrawColor(drawFilter),
                      fontWeight: FontWeight.w500,
                    ),
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


class WinningDetailsPage extends StatelessWidget {
  final String drawFilter;
  final List<BillRecord> filteredBills;

  const WinningDetailsPage({
    super.key,
    required this.drawFilter,
    required this.filteredBills,
  });

  ({double prize, double superPrize}) _totals() {
    double prize = 0;
    double superPrize = 0;
    for (final b in filteredBills) {
      for (final r in _winningRowsForBill(b, drawFilter: drawFilter)) {
        final p = (r["winningPrize"] as double?) ?? 0.0;
        prize += p;
        if (r["type"].toString().toUpperCase().endsWith("-SUPER")) {
          superPrize += p;
        }
      }
    }
    return (prize: prize, superPrize: superPrize);
  }

  String _drawCode(BillRecord bill) {
    if (bill.rows.isEmpty) return "ALL";
    final t = bill.rows.first["type"].toString().toUpperCase();
    if (t.startsWith("DEAR1")) return "DEAR1";
    if (t.startsWith("LSK3")) return "LSK3";
    if (t.startsWith("DEAR6")) return "DEAR6";
    if (t.startsWith("DEAR8")) return "DEAR8";
    return "ALL";
  }

  double _billPrize(BillRecord bill) {
    return _winningRowsForBill(bill, drawFilter: drawFilter).fold<double>(
        0.0, (s, r) => s + ((r["winningPrize"] as double?) ?? 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals();
    final tint = _salesDrawTint(drawFilter);

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
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                _salesStatChip(
                  "Prize",
                  totals.prize.toStringAsFixed(0),
                  tint,
                ),
                const SizedBox(width: 8),
                _salesStatChip(
                  "Super",
                  totals.superPrize.toStringAsFixed(0),
                  const Color(0xFFE8F5F3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ...filteredBills.map((bill) {
            final code = _drawCode(bill);
            final color = _salesDrawColor(code);
            final bg = color.withValues(alpha: 0.07);
            final prize = _billPrize(bill);
            final winningRows =
                _winningRowsForBill(bill, drawFilter: drawFilter);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Bill #${bill.billNo}",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: color,
                                ),
                              ),
                              Text(
                                bill.username,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                formatBillDateTime(bill.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₹${prize.toStringAsFixed(2)}",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _salesAccent,
                              ),
                            ),
                            Text(
                              _salesDrawLabel(code),
                              style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ...winningRows.map((row) {
                    final type = row["type"].toString();
                    final prizeLine =
                        ((row["winningPrize"] as double?) ?? 0.0)
                            .toStringAsFixed(2);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(type, style: const TextStyle(fontSize: 13)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              row["number"].toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            "${row["count"]} · ₹$prizeLine",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
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

  String _dateText(DateTime d) =>
      "${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}";

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<BillRecord> _filteredBills(List<BillRecord> bills) {
    final String ticketNo = ticketNumberController.text.trim();
    return bills.where((bill) {
      if (!_sameDate(bill.createdAt, selectedDate)) return false;
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
    final tint = _salesDrawTint(drawFilter);

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
                            _salesFieldDecoration("Ticket Number (optional)"),
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
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Bill wise search · ${_dateText(selectedDate)}",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: _salesDrawColor(drawFilter),
                      fontWeight: FontWeight.w500,
                    ),
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
  String modeFilter = "Select";

  List<BillRecord> _filteredBills(List<BillRecord> bills) {
    return bills.where((bill) {
      if (!billInDateRange(bill.createdAt, fromDate, toDate)) return false;
      if (drawFilter != "ALL" &&
          !bill.rows.any((r) => r["type"].toString().startsWith(drawFilter))) {
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
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tint = _salesDrawTint(drawFilter);

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
                        child: const Text("Generate Report"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    drawFilter == "ALL"
                        ? "All draws · sales minus winnings"
                        : "${_salesDrawLabel(drawFilter)} · net pay",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: _salesDrawColor(drawFilter),
                      fontWeight: FontWeight.w500,
                    ),
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

  double _billWinnings(BillRecord bill) {
    return _winningRowsForBill(bill, drawFilter: drawFilter).fold<double>(
        0.0, (s, r) => s + ((r["winningPrize"] as double?) ?? 0.0));
  }

  String _dateRangeText() {
    final f =
        "${fromDate.day.toString().padLeft(2, "0")}/${fromDate.month.toString().padLeft(2, "0")}/${fromDate.year}";
    final t =
        "${toDate.day.toString().padLeft(2, "0")}/${toDate.month.toString().padLeft(2, "0")}/${toDate.year}";
    return f == t ? f : "$f — $t";
  }

  Map<String, ({double sales, double win})> _userTotals() {
    final map = <String, ({double sales, double win})>{};
    for (final bill in filteredBills) {
      final user = bill.username.trim().isEmpty ? "Unknown" : bill.username;
      final prev = map[user] ?? (sales: 0.0, win: 0.0);
      map[user] = (
        sales: prev.sales + bill.totalAmount,
        win: prev.win + _billWinnings(bill),
      );
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final sales =
        filteredBills.fold<double>(0.0, (s, b) => s + b.totalAmount);
    final winnings =
        filteredBills.fold<double>(0.0, (s, b) => s + _billWinnings(b));
    final gBalance = sales - winnings;
    final nBalance = gBalance;
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(8),
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
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _salesStatChip(
                        "Sales",
                        sales.toStringAsFixed(0),
                        tint,
                      ),
                      const SizedBox(width: 8),
                      _salesStatChip(
                        "Winnings",
                        winnings.toStringAsFixed(0),
                        const Color(0xFFFFEBEE),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _salesStatChip(
                        "G. Balance",
                        gBalance.toStringAsFixed(0),
                        const Color(0xFFE8F5F3),
                      ),
                      const SizedBox(width: 8),
                      _salesStatChip(
                        "N. Balance",
                        nBalance.toStringAsFixed(0),
                        _appGradient.first.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                "Users (${sortedUsers.length})",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (sortedUsers.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      "No bills in selected range",
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              )
            else
              ...sortedUsers.map((user) {
                final totals = userTotals[user]!;
                final gBal = totals.sales - totals.win;
                final pct = totals.sales > 0
                    ? (totals.win / totals.sales * 100).toStringAsFixed(1)
                    : "0.0";

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _appGradient.first.withValues(alpha: 0.1),
                              Colors.white,
                            ],
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: _appGradient,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.person_outline,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                user,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Text(
                              "N. ₹${gBal.toStringAsFixed(0)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: _appPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Row(
                          children: [
                            _netPayMiniStat("Sale", totals.sales),
                            _netPayMiniStat("Win", totals.win),
                            _netPayMiniStat("G. Bal", gBal),
                            _netPayMiniStat("Win %", double.tryParse(pct)),
                            _netPayMiniStat("N. Bal", gBal),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _netPayMiniStat(String label, double? value) {
    final text = value == null
        ? label.contains("%")
            ? "0%"
            : "0"
        : label.contains("%")
            ? "${value.toStringAsFixed(1)}%"
            : value.toStringAsFixed(0);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
      if (!billInDateRange(bill.createdAt, selectedDate, selectedDate)) {
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
    final tint = _salesDrawTint(drawFilter);

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
                            _salesFieldDecoration("Ticket Number (optional)"),
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
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
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
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    drawFilter == "ALL"
                        ? "All draws · numbers grouped by count"
                        : "${_salesDrawLabel(drawFilter)} · number wise",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: _salesDrawColor(drawFilter),
                      fontWeight: FontWeight.w500,
                    ),
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
                    borderRadius: BorderRadius.circular(8),
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
                          borderRadius: BorderRadius.circular(6),
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
                    borderRadius: BorderRadius.circular(10),
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
                    borderRadius: BorderRadius.circular(10),
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
                            borderRadius: BorderRadius.circular(8),
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
                            gradient: LinearGradient(
                              colors: [color, color.withValues(alpha: 0.75)],
                            ),
                            borderRadius: BorderRadius.circular(8),
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: _appGradient),
            ),
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
  String modeFilter = "Select";
  DateTime fromDate = defaultReportFromDate();
  DateTime toDate = defaultReportToDate();

  @override
  void dispose() {
    ticketNumberController.dispose();
    super.dispose();
  }

  String _timeText(DateTime dt) => formatBillDateTime(dt);

  List<BillRecord> _filteredBills(List<BillRecord> bills) {
    final String ticketNo = ticketNumberController.text.trim();
    return bills.where((bill) {
      if (!billInDateRange(bill.createdAt, fromDate, toDate)) return false;
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
    final tint = _salesDrawTint(drawFilter);

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
                            _salesFieldDecoration("Ticket Number (optional)"),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _groupDropdown()),
                          const SizedBox(width: 8),
                          Expanded(
                              child: _modeDropdown()),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _appGradientButton(
                        onPressed: () {
                          final filtered = _filteredBills(bills);
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
                        child: const Text("View Bills"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    drawFilter == "ALL"
                        ? "All draws selected"
                        : "${_salesDrawLabel(drawFilter)} draw filter",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: _salesDrawColor(drawFilter),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
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
      decoration: _salesFieldDecoration("Digits"),
      items: const [
        DropdownMenuItem(value: "Select", child: Text("All")),
        DropdownMenuItem(value: "1", child: Text("1 digit")),
        DropdownMenuItem(value: "2", child: Text("2 digit")),
        DropdownMenuItem(value: "3", child: Text("3 digit")),
      ],
      onChanged: (v) => setState(() => groupFilter = v ?? "Select"),
    );
  }

  Widget _modeDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: modeFilter,
      decoration: _salesFieldDecoration("Mode"),
      items: const [
        DropdownMenuItem(value: "Select", child: Text("All")),
        DropdownMenuItem(value: "Mode", child: Text("Mode")),
      ],
      onChanged: (v) => setState(() => modeFilter = v ?? "Select"),
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
        decoration: _salesFieldDecoration(label),
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
            const SizedBox(height: 6),
            Text(
              "Count : 0  ·  Amount : 0.00",
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
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

  @override
  void initState() {
    super.initState();
    _bills = List<BillRecord>.from(widget.filteredBills);
  }

  Future<void> _confirmDeleteBill(BillRecord bill) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete bill?"),
        content: Text(
          "Bill #${bill.billNo} and receipt will be permanently deleted.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    BillsStore.delete(bill.billNo);
    setState(() => _bills.removeWhere((b) => b.billNo == bill.billNo));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Bill #${bill.billNo} deleted")),
    );

    if (_bills.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _editRow(BillRecord bill, int index) async {
    if (index < 0 || index >= bill.rows.length) return;
    final row = bill.rows[index];
    final numberEditController =
        TextEditingController(text: row["number"].toString());
    final countEditController =
        TextEditingController(text: row["count"].toString());

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Edit Number"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numberEditController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Number"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: countEditController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Count"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Save"),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final String updatedNumber = numberEditController.text.trim();
    final int updatedCount = int.tryParse(countEditController.text.trim()) ?? 0;
    if (updatedNumber.isEmpty || updatedCount <= 0) return;

    final int oldCount = int.tryParse(row["count"].toString()) ?? 1;
    final double oldAmount = (row["amount"] as double?) ?? 0.0;
    final double unitRate = oldCount > 0 ? oldAmount / oldCount : 0.0;

    setState(() {
      row["number"] = updatedNumber;
      row["count"] = updatedCount.toString();
      row["amount"] = unitRate * updatedCount;
    });
    BillsStore.notifyUpdated(bill);
  }

  void _deleteRow(BillRecord bill, int index) {
    if (index < 0 || index >= bill.rows.length) return;
    setState(() => bill.rows.removeAt(index));
    BillsStore.notifyUpdated(bill);
  }

  Future<void> _showRowActions(BillRecord bill, int index) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Edit"),
              onTap: () => Navigator.pop(ctx, "edit"),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete"),
              onTap: () => Navigator.pop(ctx, "delete"),
            ),
          ],
        ),
      ),
    );
    if (action == "edit") {
      await _editRow(bill, index);
    } else if (action == "delete") {
      _deleteRow(bill, index);
    }
  }

  String _drawCode(BillRecord bill) {
    if (bill.rows.isEmpty) return "ALL";
    final t = bill.rows.first["type"].toString().toUpperCase();
    if (t.startsWith("DEAR1")) return "DEAR1";
    if (t.startsWith("LSK3")) return "LSK3";
    if (t.startsWith("DEAR6")) return "DEAR6";
    if (t.startsWith("DEAR8")) return "DEAR8";
    return "ALL";
  }

  @override
  Widget build(BuildContext context) {
    final int totalQty = _bills.fold<int>(0, (s, b) => s + b.totalCount);
    final double totalAmount =
        _bills.fold<double>(0.0, (s, b) => s + b.totalAmount);
    final tint = _salesDrawTint(widget.drawFilter);

    return _reportPage(context: context, title: "Bill Details", body: _bills.isEmpty
          ? const _SalesReportEmptyBody()
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      _salesStatChip(
                        "Amount",
                        totalAmount.toStringAsFixed(0),
                        tint,
                      ),
                      const SizedBox(width: 8),
                      _salesStatChip(
                        "Qty",
                        "$totalQty",
                        const Color(0xFFE8F5F3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ..._bills.map((bill) {
                  final code = _drawCode(bill);
                  final color = _salesDrawColor(code);
                  final bg = color.withValues(alpha: 0.07);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Bill #${bill.billNo}",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        color: color,
                                      ),
                                    ),
                                    Text(
                                      widget.timeTextBuilder(bill.createdAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "₹${bill.totalAmount.toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    "Qty ${bill.totalCount}",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () => _confirmDeleteBill(bill),
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red.shade400,
                                tooltip: 'Delete bill',
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                        if (bill.rows.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              "No lines",
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        else
                          ...bill.rows.asMap().entries.map((entry) {
                            final index = entry.key;
                            final row = entry.value;
                            final amount =
                                ((row["amount"] as double?) ?? 0.0)
                                    .toStringAsFixed(2);
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onLongPress: () =>
                                    _showRowActions(bill, index),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          row["type"].toString(),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          row["number"].toString(),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        "${row["count"]} × $amount",
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _confirmDeleteBill(bill),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text("Delete Bill & Receipt"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade200),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
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

  @override
  void initState() {
    super.initState();
    billNoController = TextEditingController(
      text: widget.initialBillNo?.toString() ?? "",
    );
    selectedBill = widget.initialBillNo == null
        ? null
        : BillsStore.byBillNo(widget.initialBillNo!);
  }

  @override
  void dispose() {
    billNoController.dispose();
    super.dispose();
  }

  void _search() {
    final int? billNo = int.tryParse(billNoController.text.trim());
    if (billNo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid bill number")),
      );
      return;
    }
    final BillRecord? bill = BillsStore.byBillNo(billNo);
    setState(() => selectedBill = bill);
    if (bill == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Bill #$billNo not found")),
      );
    }
  }

  void _deleteBill() {
    final int? billNo = int.tryParse(billNoController.text.trim());
    if (billNo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid bill number")),
      );
      return;
    }
    if (BillsStore.byBillNo(billNo) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Bill #$billNo not found")),
      );
      return;
    }
    BillsStore.delete(billNo);
    setState(() => selectedBill = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Bill #$billNo deleted")),
    );
  }

  void _deleteRow(int index) {
    if (selectedBill == null) return;
    setState(() => selectedBill!.rows.removeAt(index));
    BillsStore.notifyUpdated(selectedBill);
  }

  Future<void> _editRow(int index) async {
    if (selectedBill == null) return;
    final row = selectedBill!.rows[index];
    final numberEditController =
        TextEditingController(text: row["number"].toString());
    final countEditController =
        TextEditingController(text: row["count"].toString());

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Edit Row"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numberEditController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Number"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: countEditController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Count"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Save")),
        ],
      ),
    );
    if (ok != true) return;

    final String updatedNumber = numberEditController.text.trim();
    final int updatedCount = int.tryParse(countEditController.text.trim()) ?? 0;
    if (updatedNumber.isEmpty || updatedCount <= 0) return;

    final int oldCount = int.tryParse(row["count"].toString()) ?? 1;
    final double oldAmount = (row["amount"] as double?) ?? 0.0;
    final double unitRate = oldCount > 0 ? oldAmount / oldCount : 0.0;

    setState(() {
      row["number"] = updatedNumber;
      row["count"] = updatedCount.toString();
      row["amount"] = unitRate * updatedCount;
    });
    BillsStore.notifyUpdated(selectedBill);
  }

  String _formatDate(DateTime dt) =>
      "${dt.year.toString().padLeft(4, "0")}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}";

  String _formatTime(DateTime dt) {
    final int hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final String ampm = dt.hour >= 12 ? "PM" : "AM";
    return "${dt.month}/${dt.day}, $hour12:${dt.minute.toString().padLeft(2, "0")} $ampm";
  }

  Color _gameColorFromBill(BillRecord? bill) {
    if (bill == null || bill.rows.isEmpty) return Colors.blue;
    final String type = bill.rows.first["type"].toString().toUpperCase();
    if (type.startsWith("DEAR1")) return const Color(0xFF1565C0);
    if (type.startsWith("DEAR6")) return const Color(0xFF6A1B9A);
    if (type.startsWith("DEAR8")) return const Color(0xFFAD1457);
    if (type.startsWith("LSK3")) return const Color(0xFF2E7D32);
    return Colors.blue;
  }

  String _gameNameFromBill(BillRecord? bill) {
    if (bill == null || bill.rows.isEmpty) return "-";
    final String type = bill.rows.first["type"].toString().toUpperCase();
    if (type.startsWith("DEAR1")) return "DEAR 1 PM";
    if (type.startsWith("LSK3")) return "LSK 3 PM";
    if (type.startsWith("DEAR6")) return "DEAR 6 PM";
    if (type.startsWith("DEAR8")) return "DEAR 8 PM";
    return type;
  }

  @override
  Widget build(BuildContext context) {
    final bill = selectedBill;
    final themeColor = _gameColorFromBill(bill);
    final gameName = _gameNameFromBill(bill);

    return _reportPage(
      context: context,
      title: 'Edit / Delete',
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
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
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bill #${bill.billNo}',
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
                    '${_formatDate(bill.createdAt)} · ${_formatTime(bill.createdAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
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
                  ((row['amount'] as double?) ?? 0.0).toStringAsFixed(2);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
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
                  trailing: Row(
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
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

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

  /// Start / End / Count labels only when Range, Range 2, 100, or 111 is on.
  bool get _usesStartEndCountLayout => isRangeMode;
  bool get showThirdField => isTripleMode || isRangeMode;
  static const List<Color> _saveButtonGradient = [
    Color(0xFF00ACC1),
    Color(0xFF006064),
  ];

  @override
  void initState() {
    super.initState();
    selectedTime = widget.title;
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    numberController.dispose();
    countController.dispose();
    boxController.dispose();
    numberFocusNode.dispose();
    countFocusNode.dispose();
    boxFocusNode.dispose();
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [_topPanel(), _listPanel()],
                ),
              ),
            ),
            _bottomSummary(),
          ],
        ),
      ),
    );
  }

  Widget _topPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              selectBox("1"),
              selectBox("2"),
              selectBox("3"),
              const Spacer(),
              SizedBox(
                height: 40,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _liveTimeLightGradient(selectedTime),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _timeColor(selectedTime).withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Text(_liveTimeText(),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 108,
                height: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: selectedEntries.isNotEmpty
                          ? _saveButtonGradient
                          : const [Color(0xFF9E9E9E), Color(0xFF757575)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed:
                        selectedEntries.isNotEmpty ? _saveCurrentBooking : null,
                    child: const Text("SAVE"),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _timeSelectorBox(),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                optionBox("Range", "range"),
                const SizedBox(width: 8),
                optionBox("Range 2", "range2"),
                const SizedBox(width: 8),
                optionBox("Set Box", "set"),
                const SizedBox(width: 8),
                optionBox("100", "100"),
                const SizedBox(width: 8),
                optionBox("111", "111"),
                const SizedBox(width: 12),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: numberController,
                  focusNode: numberFocusNode,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 17,
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
                  decoration: InputDecoration(
                    labelText: _usesStartEndCountLayout ? "Start" : "Number",
                    filled: false,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.shade500,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: countController,
                  focusNode: countFocusNode,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 17,
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
                  decoration: InputDecoration(
                    labelText: _usesStartEndCountLayout ? "End" : "Count",
                    filled: false,
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.shade400,
                        width: 1.0,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.shade500,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              if (showThirdField) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: boxController,
                    focusNode: boxFocusNode,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 17,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: _usesStartEndCountLayout ? "Count" : "Box",
                      filled: false,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.grey.shade400,
                          width: 1.0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.grey.shade500,
                          width: 1.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: _modeButtons().map((label) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: actionBtn(label),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _listPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Container(
            color: Colors.green.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Count: ${_totalCount()}",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text("Total: ${_totalAmount().toStringAsFixed(2)}",
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          ...selectedEntries.asMap().entries.map((entry) {
            final int index = entry.key;
            final row = entry.value;
            final bool isMathy =
                isRangeMode || (row["type"] as String).contains("BOX");

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: Colors.grey.shade300))),
              child: Row(
                children: [
                  Expanded(
                      flex: 4,
                      child: Text(
                        row["type"] as String,
                        style: const TextStyle(fontSize: 14),
                      )),
                  Expanded(
                      flex: 2,
                      child: Text(
                        row["number"] as String,
                        style: TextStyle(
                          fontFamily: isMathy ? 'monospace' : null,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      )),
                  Expanded(
                      flex: 2,
                      child: Text(
                        row["count"] as String,
                        style: TextStyle(
                          fontFamily: isMathy ? 'monospace' : null,
                          fontWeight: FontWeight.w500,
                        ),
                      )),
                  Expanded(
                      flex: 3,
                      child: Text(
                        (row["amount"] as double).toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      )),
                  IconButton(
                    onPressed: () =>
                        setState(() => selectedEntries.removeAt(index)),
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _bottomSummary() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Commition: ${_commission().toStringAsFixed(2)}",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              Text("Total Collect: ${_totalAmount().toStringAsFixed(2)}",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: bottomBtn("CLEAR", Colors.grey)),
              const SizedBox(width: 8),
              Expanded(child: bottomBtn("Home", Colors.red)),
              const SizedBox(width: 8),
              Expanded(child: bottomBtn("Message", Colors.teal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget selectBox(String text) {
    final bool isSelected = selectedOption == text;
    final Color gameColor = _timeColor(selectedTime);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
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
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: gameColor,
              size: 26,
            ),
            const SizedBox(width: 4),
            Text(text),
          ],
        ),
      ),
    );
  }

  Widget optionBox(String label, String key) {
    final bool isSelected = _isPatternSelected(key);
    final bool disabled = isSingleDigitMode;
    final Color gameColor = _timeColor(selectedTime);
    final List<Color> gameGradient = _timeGradient(selectedTime);
    return InkWell(
      onTap: disabled ? null : () => _onExclusiveCheck(key, !isSelected),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? LinearGradient(colors: gameGradient) : null,
          color: isSelected ? null : Colors.white,
          border:
              Border.all(color: isSelected ? gameColor : Colors.grey.shade400),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: disabled
                ? Colors.grey
                : (isSelected ? Colors.white : Colors.black87),
            fontWeight: FontWeight.w500,
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

  Widget actionBtn(String text) {
    final List<Color> gameGradient = _timeGradient(selectedTime);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gameGradient),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: () {
          final String inputNumber = numberController.text.trim();
          final String inputSecond = countController.text.trim();
          final String inputThird = boxController.text.trim();
          if (inputNumber.isEmpty || inputSecond.isEmpty) return;
          final bool isSimpleTriple = isTripleHundredDefault &&
              inputThird.isEmpty &&
              inputNumber.length == 3;
          final bool isSplitSuperBoxMode =
              isTripleMode && !isRangeMode && !isSimpleTriple;

          if (_usesStartEndCountLayout &&
              !isSimpleTriple &&
              inputThird.isEmpty) {
            return;
          }

          final int superCountInput = int.tryParse(inputSecond) ?? 0;
          final int boxCountInput = int.tryParse(inputThird) ?? 0;

          // Trial rule requested:
          // In triple booking, Count -> SUPER and Box field -> BOX count.
          if (isSplitSuperBoxMode) {
            if (superCountInput <= 0) return;
            if ((text == "BOTH" || text.endsWith("-BOX")) &&
                boxCountInput <= 0) {
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

          setState(() {
            for (final type in types) {
              for (final n in numbers) {
                int rowCount = countVal;
                if (isSplitSuperBoxMode) {
                  if (type.endsWith("-SUPER")) {
                    rowCount = superCountInput;
                  } else if (type.endsWith("-BOX")) {
                    rowCount =
                        boxCountInput > 0 ? boxCountInput : superCountInput;
                  } else {
                    rowCount = superCountInput;
                  }
                }
                if (rowCount <= 0) continue;

                final double rate = _rateForType(type);
                final double amount = rowCount * rate;
                selectedEntries.insert(0, {
                  "type": type,
                  "number": n,
                  "count": rowCount.toString(),
                  "amount": amount,
                });
              }
            }
            numberController.clear();
            countController.clear();
            boxController.clear();
          });
          FocusScope.of(context).requestFocus(numberFocusNode);
        },
        child: Text(text),
      ),
    );
  }

  Widget bottomBtn(String text, Color color) {
    final String key = text.toUpperCase();
    final List<Color> gradient;
    switch (key) {
      case "CLEAR":
        gradient = const [Color(0xFF90A4AE), Color(0xFF546E7A)];
        break;
      case "HOME":
        gradient = const [Color(0xFFEF5350), Color(0xFFC62828)];
        break;
      case "MESSAGE":
        gradient = const [Color(0xFF4DB6AC), Color(0xFF00695C)];
        break;
      default:
        gradient = [color, color];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          if (key == "CLEAR") {
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
      return ["$code-AB", "$code-BC", "$code-AC", "ALL"];
    }
    return ["$code-SUPER", "$code-BOX", "BOTH"];
  }

  Future<void> _importEntriesFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final String raw = (data?.text ?? "").trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Clipboard-ൽ data ഇല്ല")),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Number/Count format മനസ്സിലായില്ല")),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${rows.length} entries add ചെയ്തു")),
    );
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
      final double rate = _rateForImportedType(type);
      for (final expanded
          in _expandImportedNumbers(number, forceSetExpand: forceSetExpand)) {
        parsed.add({
          "type": type,
          "number": expanded,
          "count": count.toString(),
          "amount": rate * count,
        });
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

  double _rateForImportedType(String type) {
    final suffix = type.split("-").last.toUpperCase();
    return (suffix == "A" || suffix == "B" || suffix == "C") ? 12.0 : 10.0;
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

  double _rateForType(String type) => selectedOption == "1" ? 12.0 : 10.0;

  int _totalCount() => selectedEntries.fold<int>(
      0, (total, row) => total + (int.tryParse(row["count"].toString()) ?? 0));

  double _totalAmount() => selectedEntries.fold<double>(
      0.0, (total, row) => total + ((row["amount"] as double?) ?? 0.0));

  double _commission() => 0.0;

  Color _timeColor(String time) {
    switch (time) {
      case "DEAR 1 PM":
        return const Color(0xFF1565C0);
      case "DEAR 6 PM":
        return const Color(0xFF6A1B9A);
      case "DEAR 8 PM":
        return const Color(0xFFAD1457);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  List<Color> _timeGradient(String time) {
    switch (time) {
      case "DEAR 1 PM":
        return const [Color(0xFF1976D2), Color(0xFF0D47A1)];
      case "DEAR 6 PM":
        return const [Color(0xFF8E24AA), Color(0xFF4A148C)];
      case "DEAR 8 PM":
        return const [Color(0xFFD81B60), Color(0xFF880E4F)];
      default:
        return const [Color(0xFF43A047), Color(0xFF1B5E20)];
    }
  }

  List<Color> _liveTimeLightGradient(String time) {
    switch (time) {
      case "DEAR 1 PM":
        return const [Color(0xFFEAF4FF), Color(0xFFDDEEFF)];
      case "DEAR 6 PM":
        return const [Color(0xFFF4ECFB), Color(0xFFE9DDF8)];
      case "DEAR 8 PM":
        return const [Color(0xFFFDEAF3), Color(0xFFF8DBE9)];
      default:
        return const [Color(0xFFECF8EE), Color(0xFFDDF2E1)];
    }
  }

  String _liveTimeText() {
    final int hour12 = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final String ampm = _now.hour >= 12 ? "PM" : "AM";
    return "$hour12:${_now.minute.toString().padLeft(2, "0")}:${_now.second.toString().padLeft(2, "0")} $ampm";
  }

  Widget _timeSelectorBox() {
    const times = ["DEAR 1 PM", "LSK 3 PM", "DEAR 6 PM", "DEAR 8 PM"];
    final int currentIndex = times.indexOf(selectedTime);
    final int safeIndex = currentIndex >= 0 ? currentIndex : 0;
    final List<Color> gradient = _timeGradient(selectedTime);

    return SizedBox(
      width: 120,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          onPressed: () {
            final bool hasWorkingInput =
                numberController.text.trim().isNotEmpty ||
                    countController.text.trim().isNotEmpty ||
                    boxController.text.trim().isNotEmpty ||
                    selectedEntries.isNotEmpty;
            if (hasWorkingInput) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text("Number/Coupon clear ചെയ്താൽ മാത്രം game മാറ്റാം"),
                ),
              );
              return;
            }
            final int next = (safeIndex + 1) % times.length;
            setState(() => selectedTime = times[next]);
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              selectedTime,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  bool autoSubmit = false;

  bool _handleWhatsAppPaste(String text) {
    final result = parseWhatsAppFull(text);
    final List<Booking> bookings = result['bookings'];
    if (bookings.isEmpty) return false;

    setState(() {
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

        final double rate = _rateForImportedType(type);
        final bool isSet = b.category == BookingCategory.permutation;

        for (final expanded
            in _expandImportedNumbers(b.itemNumber, forceSetExpand: isSet)) {
          selectedEntries.insert(0, {
            "type": type,
            "number": expanded,
            "count": b.quantity.toString(),
            "amount": rate * b.quantity,
          });
        }
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${bookings.length} entries imported")),
      );
    }

    if (autoSubmit) {
      _saveCurrentBooking();
    }
    return true;
  }

  void _saveCurrentBooking() {
    if (selectedEntries.isEmpty) return;

    for (final row in selectedEntries) {
      SalesStore.add(
        SaleEntry(
          type: row["type"] as String,
          number: row["number"] as String,
          count: int.tryParse(row["count"].toString()) ?? 0,
          amount: (row["amount"] as double?) ?? 0.0,
          time: selectedTime,
          createdAt: DateTime.now(),
        ),
      );
    }

    final int billNo = 400000 + Random().nextInt(99999);
    final Color gameColor = _timeColor(selectedTime);
    final billRows =
        selectedEntries.map((e) => Map<String, dynamic>.from(e)).toList();
    BillsStore.add(
      BillRecord(
        billNo: billNo,
        createdAt: DateTime.now(),
        rows: billRows,
        username: widget.username,
      ),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [gameColor, gameColor.withValues(alpha: 0.75)],
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: const Text(
                  "😎  Success",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 36),
              Text("Bill No #$billNo", style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 36),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              gameColor,
                              gameColor.withValues(alpha: 0.75)
                            ],
                          ),
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero),
                          ),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            Navigator.push(
                              context,
                              appRoute(
                                EditBillPage(initialBillNo: billNo),
                              ),
                            );
                          },
                          child: const Text("View Bill"),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero),
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text("OK"),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    setState(() {
      selectedEntries.clear();
      numberController.clear();
      countController.clear();
      boxController.clear();
    });
    FocusScope.of(context).requestFocus(numberFocusNode);
  }
}
