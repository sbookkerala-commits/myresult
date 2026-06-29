import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database/local_database.dart';
import 'app_messages.dart';

const List<String> kDrawTimeNames = [
  'DEAR 1 PM',
  'LSK 3 PM',
  'DEAR 6 PM',
  'DEAR 8 PM',
];

class DrawSchedule {
  final String drawTime;
  final int openHour;
  final int openMinute;
  final int closeHour;
  final int closeMinute;

  const DrawSchedule({
    required this.drawTime,
    required this.openHour,
    required this.openMinute,
    required this.closeHour,
    required this.closeMinute,
  });

  Map<String, dynamic> toJson() => {
        'drawTime': drawTime,
        'openHour': openHour,
        'openMinute': openMinute,
        'closeHour': closeHour,
        'closeMinute': closeMinute,
      };

  static DrawSchedule? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final drawTime = json['drawTime']?.toString() ?? '';
    if (drawTime.isEmpty) return null;
    int readInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }
    return DrawSchedule(
      drawTime: drawTime,
      openHour: readInt(json['openHour'], 7),
      openMinute: readInt(json['openMinute'], 0),
      closeHour: readInt(json['closeHour'], 13),
      closeMinute: readInt(json['closeMinute'], 0),
    );
  }

  DrawSchedule copyWith({
    int? openHour,
    int? openMinute,
    int? closeHour,
    int? closeMinute,
  }) {
    return DrawSchedule(
      drawTime: drawTime,
      openHour: openHour ?? this.openHour,
      openMinute: openMinute ?? this.openMinute,
      closeHour: closeHour ?? this.closeHour,
      closeMinute: closeMinute ?? this.closeMinute,
    );
  }
}

DrawSchedule _defaultScheduleFor(String drawTime) {
  switch (drawTime) {
    case 'DEAR 1 PM':
      return DrawSchedule(
        drawTime: drawTime,
        openHour: 7,
        openMinute: 0,
        closeHour: 13,
        closeMinute: 0,
      );
    case 'LSK 3 PM':
      return DrawSchedule(
        drawTime: drawTime,
        openHour: 7,
        openMinute: 0,
        closeHour: 15,
        closeMinute: 0,
      );
    case 'DEAR 6 PM':
      return DrawSchedule(
        drawTime: drawTime,
        openHour: 7,
        openMinute: 0,
        closeHour: 18,
        closeMinute: 0,
      );
    case 'DEAR 8 PM':
      return DrawSchedule(
        drawTime: drawTime,
        openHour: 7,
        openMinute: 0,
        closeHour: 20,
        closeMinute: 0,
      );
    default:
      return DrawSchedule(
        drawTime: drawTime,
        openHour: 7,
        openMinute: 0,
        closeHour: 20,
        closeMinute: 0,
      );
  }
}

String formatDrawScheduleTime(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  final ampm = hour >= 12 ? 'PM' : 'AM';
  return '$h:${minute.toString().padLeft(2, '0')} $ampm';
}

class DrawScheduleStore {
  static const _prefsKey = 'draw_schedules_v1';

  static final ValueNotifier<Map<String, DrawSchedule>> schedules =
      ValueNotifier<Map<String, DrawSchedule>>({
    for (final name in kDrawTimeNames) name: _defaultScheduleFor(name),
  });

  static Future<void> init() async {
    final raw = await LocalDatabase.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _applyMap(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('DrawScheduleStore load error: $e');
    }
  }

  static void _applyMap(Map<String, dynamic> raw) {
    final next = <String, DrawSchedule>{
      for (final name in kDrawTimeNames) name: _defaultScheduleFor(name),
    };
    for (final name in kDrawTimeNames) {
      final item = raw[name];
      if (item is Map) {
        final s = DrawSchedule.fromJson(Map<String, dynamic>.from(item));
        if (s != null) next[name] = s;
      }
    }
    schedules.value = next;
  }

  static DrawSchedule scheduleFor(String drawTime) {
    return schedules.value[drawTime.trim()] ??
        _defaultScheduleFor(drawTime.trim());
  }

  static int _minutes(int hour, int minute) => hour * 60 + minute;

  static DateTime _atTime(DateTime base, int hour, int minute) =>
      DateTime(base.year, base.month, base.day, hour, minute);

  static DateTime nextCloseDateTime(String drawTime, {DateTime? at}) {
    final s = scheduleFor(drawTime);
    final now = at ?? DateTime.now();
    final openM = _minutes(s.openHour, s.openMinute);
    final closeM = _minutes(s.closeHour, s.closeMinute);
    final nowM = _minutes(now.hour, now.minute);

    if (openM <= closeM) {
      return _atTime(now, s.closeHour, s.closeMinute);
    }

    if (nowM >= openM) {
      final tomorrow = now.add(const Duration(days: 1));
      return _atTime(tomorrow, s.closeHour, s.closeMinute);
    }
    return _atTime(now, s.closeHour, s.closeMinute);
  }

  static Duration closeCountdown(String drawTime, {DateTime? at}) {
    final now = at ?? DateTime.now();
    return nextCloseDateTime(drawTime, at: now).difference(now);
  }

  static String formatCountdown(Duration duration) {
    final totalSec = duration.inSeconds.clamp(0, 86400 * 2);
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    final s = totalSec % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  /// When booking is open, returns HH:MM:SS left until close. Otherwise null.
  static String? bookingCloseCountdownText(String drawTime, {DateTime? at}) {
    if (!isDrawBookingOpen(drawTime, at: at)) return null;
    return formatCountdown(closeCountdown(drawTime, at: at));
  }

  /// When booking is open, shows time left until close. Otherwise null.
  static String? bookingCloseCountdownLabel(String drawTime, {DateTime? at}) {
    final cd = bookingCloseCountdownText(drawTime, at: at);
    if (cd == null) return null;
    return 'Close in $cd';
  }

  static bool _isScheduledDrawBookingOpen(String drawTime, {DateTime? at}) {
    final s = scheduleFor(drawTime);
    final now = at ?? DateTime.now();
    final nowM = _minutes(now.hour, now.minute);
    final openM = _minutes(s.openHour, s.openMinute);
    final closeM = _minutes(s.closeHour, s.closeMinute);
    if (openM <= closeM) {
      return nowM >= openM && nowM <= closeM;
    }
    return nowM >= openM || nowM <= closeM;
  }

  static bool isDrawBookingOpen(String drawTime, {DateTime? at}) {
    return _isScheduledDrawBookingOpen(drawTime, at: at);
  }

  /// Business date for a booking on [drawTime] at [at] (admin close-time rule).
  /// After close → next calendar day. Overnight open: evening after open → next day.
  static DateTime businessDateForDraw(String drawTime, {DateTime? at}) {
    final now = (at ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final nowM = _minutes(now.hour, now.minute);
    final s = scheduleFor(drawTime);
    final openM = _minutes(s.openHour, s.openMinute);
    final closeM = _minutes(s.closeHour, s.closeMinute);

    if (openM > closeM) {
      if (nowM >= openM) return today.add(const Duration(days: 1));
      return today;
    }
    if (nowM > closeM) return today.add(const Duration(days: 1));
    return today;
  }

  /// Active business date for reports/lists (latest close rule across draws).
  static DateTime currentBusinessDate({DateTime? at, List<String>? drawNames}) {
    final now = (at ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final names = drawNames ?? kDrawTimeNames;
    var result = today;
    for (final name in names) {
      final bd = businessDateForDraw(name, at: now);
      final day = DateTime(bd.year, bd.month, bd.day);
      if (day.isAfter(result)) result = day;
    }
    return result;
  }

  @Deprecated('Use businessDateForDraw')
  static DateTime bookingSalesDate(String drawTime, {DateTime? at}) =>
      businessDateForDraw(drawTime, at: at);

  /// Default sales / winning / net-pay report date — admin business day.
  static DateTime salesReportDate({DateTime? at, List<String>? drawNames}) =>
      currentBusinessDate(at: at, drawNames: drawNames);

  static String drawCloseTimeLabel(String drawTime) {
    final s = scheduleFor(drawTime);
    return formatDrawScheduleTime(s.closeHour, s.closeMinute);
  }

  static String drawResultTimeLabel(String drawTime) {
    switch (drawTime.trim()) {
      case 'DEAR 1 PM':
        return '1:00 PM';
      case 'LSK 3 PM':
        return '3:00 PM';
      case 'DEAR 6 PM':
        return '6:00 PM';
      case 'DEAR 8 PM':
        return '8:00 PM';
      default:
        return drawCloseTimeLabel(drawTime);
    }
  }

  /// Active draw for booking: earliest-closing open draw, else next/upcoming for today.
  static String currentDraw({DateTime? at, List<String>? allowed}) {
    final names = allowed ?? kDrawTimeNames;
    if (names.isEmpty) return kDrawTimeNames.first;
    final now = at ?? DateTime.now();
    final nowM = _minutes(now.hour, now.minute);

    String? bestOpen;
    var bestCloseM = 9999;
    for (final name in names) {
      if (!isDrawBookingOpen(name, at: now)) continue;
      final s = scheduleFor(name);
      final closeM = _minutes(s.closeHour, s.closeMinute);
      if (closeM < bestCloseM) {
        bestCloseM = closeM;
        bestOpen = name;
      }
    }
    if (bestOpen != null) return bestOpen;

    for (final name in names) {
      final s = scheduleFor(name);
      final openM = _minutes(s.openHour, s.openMinute);
      if (nowM < openM) return name;
    }
    return names.first;
  }

  static String _nextAllowedDraw(String draw, List<String> names) {
    final idx = kDrawTimeNames.indexOf(draw);
    if (idx < 0) return names.first;
    for (var i = 1; i <= kDrawTimeNames.length; i++) {
      final next = kDrawTimeNames[(idx + i) % kDrawTimeNames.length];
      if (names.contains(next)) return next;
    }
    return names.first;
  }

  /// Menu header draw: after a draw closes, show the next draw (1→3→6→8→1).
  static String currentMenuDraw({DateTime? at, List<String>? allowed}) {
    final names = allowed ?? kDrawTimeNames;
    if (names.isEmpty) return kDrawTimeNames.first;
    final now = at ?? DateTime.now();
    final nowM = _minutes(now.hour, now.minute);

    String? lastClosed;
    for (final name in kDrawTimeNames) {
      if (!names.contains(name)) continue;
      final s = scheduleFor(name);
      final closeM = _minutes(s.closeHour, s.closeMinute);
      if (nowM > closeM) {
        lastClosed = name;
      }
    }

    if (lastClosed != null) {
      final next = _nextAllowedDraw(lastClosed, names);
      if (isDrawBookingOpen(next, at: now)) return next;
    }

    return currentDraw(at: at, allowed: names);
  }

  /// UI theme draw: last draw whose close time passed — until the next draw closes.
  /// After LSK 3 PM closes, stay LSK-colored until DEAR 6 PM close (not when DEAR 6 booking opens).
  /// Before today's first draw closes (e.g. 3 AM), returns yesterday's last draw (DEAR 8 PM).
  static String currentUiDraw({DateTime? at, List<String>? allowed}) {
    final names = allowed ?? kDrawTimeNames;
    if (names.isEmpty) return kDrawTimeNames.first;
    final now = at ?? DateTime.now();
    final nowM = _minutes(now.hour, now.minute);

    final ordered = [...names]
      ..sort((a, b) {
        final sa = scheduleFor(a);
        final sb = scheduleFor(b);
        return _minutes(sa.closeHour, sa.closeMinute)
            .compareTo(_minutes(sb.closeHour, sb.closeMinute));
      });

    String? lastClosed;
    for (final name in ordered) {
      final s = scheduleFor(name);
      final closeM = _minutes(s.closeHour, s.closeMinute);
      if (nowM >= closeM) {
        lastClosed = name;
      }
    }
    return lastClosed ?? ordered.last;
  }

  /// Result-page calendar date paired with [currentUiDraw].
  /// Before today's first draw closes, uses yesterday (last night's DEAR 8 PM result).
  static DateTime currentUiDrawResultDate({DateTime? at, List<String>? allowed}) {
    final now = (at ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final names = allowed ?? kDrawTimeNames;
    if (names.isEmpty) return today;

    final ordered = [...names]
      ..sort((a, b) {
        final sa = scheduleFor(a);
        final sb = scheduleFor(b);
        return _minutes(sa.closeHour, sa.closeMinute)
            .compareTo(_minutes(sb.closeHour, sb.closeMinute));
      });

    final firstCloseM = _minutes(
      scheduleFor(ordered.first).closeHour,
      scheduleFor(ordered.first).closeMinute,
    );
    final nowM = _minutes(now.hour, now.minute);
    if (nowM < firstCloseM) {
      return today.subtract(const Duration(days: 1));
    }
    return today;
  }

  static String scheduleWindowLabel(String drawTime) {
    final s = scheduleFor(drawTime);
    return '${formatDrawScheduleTime(s.openHour, s.openMinute)} – '
        '${formatDrawScheduleTime(s.closeHour, s.closeMinute)}';
  }

  static String? drawBookingBlockMessage(String drawTime, {DateTime? at}) {
    if (isDrawBookingOpen(drawTime, at: at)) return null;
    final s = scheduleFor(drawTime);
    return AppMsg.bookingClosed(
      formatDrawScheduleTime(s.openHour, s.openMinute),
      formatDrawScheduleTime(s.closeHour, s.closeMinute),
    );
  }

  static String drawTimeFromRowType(String type) {
    final t = type.trim().toUpperCase();
    if (t.startsWith('DEAR1')) return 'DEAR 1 PM';
    if (t.startsWith('LSK3')) return 'LSK 3 PM';
    if (t.startsWith('DEAR6')) return 'DEAR 6 PM';
    if (t.startsWith('DEAR8')) return 'DEAR 8 PM';
    return kDrawTimeNames.first;
  }

  /// Saved bills can be edited/deleted only on the same day while booking is open.
  static bool isBillModifiable({
    required DateTime billBusinessDate,
    required String drawTime,
    DateTime? at,
  }) {
    final now = (at ?? DateTime.now()).toLocal();
    final billDay = DateTime(
      billBusinessDate.year,
      billBusinessDate.month,
      billBusinessDate.day,
    );
    final expectedDay = businessDateForDraw(drawTime, at: now);
    if (billDay != expectedDay) return false;
    return isDrawBookingOpen(drawTime, at: now);
  }

  static String? billModifyBlockMessage({
    required DateTime billBusinessDate,
    required String drawTime,
    DateTime? at,
  }) {
    if (isBillModifiable(
      billBusinessDate: billBusinessDate,
      drawTime: drawTime,
      at: at,
    )) {
      return null;
    }
    final now = (at ?? DateTime.now()).toLocal();
    final billDay = DateTime(
      billBusinessDate.year,
      billBusinessDate.month,
      billBusinessDate.day,
    );
    final expectedDay = businessDateForDraw(drawTime, at: now);
    if (billDay != expectedDay) {
      return AppMsg.pastDrawReceiptBlocked;
    }
    return drawBookingBlockMessage(drawTime, at: now) ??
        AppMsg.bookingClosedEditBlocked;
  }

  static Future<void> saveNow() async {
    final payload = jsonEncode({
      for (final e in schedules.value.entries) e.key: e.value.toJson(),
    });
    await LocalDatabase.setString(_prefsKey, payload);
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, payload);
  }

  static void replaceFromCloud(Map<String, dynamic> raw) {
    if (raw.isEmpty) return;
    _applyMap(raw);
    unawaited(saveNow());
  }

  static Future<void> updateSchedule(DrawSchedule schedule) async {
    final next = Map<String, DrawSchedule>.from(schedules.value);
    next[schedule.drawTime] = schedule;
    schedules.value = next;
    await saveNow();
  }

  static Future<void> replaceAll(Map<String, DrawSchedule> map) async {
    final next = <String, DrawSchedule>{
      for (final name in kDrawTimeNames) name: _defaultScheduleFor(name),
    };
    for (final name in kDrawTimeNames) {
      final s = map[name];
      if (s != null) next[name] = s;
    }
    schedules.value = next;
    await saveNow();
  }
}
