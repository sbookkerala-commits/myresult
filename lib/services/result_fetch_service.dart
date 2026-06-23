import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'dear_lottery_in_source.dart';
import 'fetched_result_data.dart';

export 'fetched_result_data.dart';

class ResultFetchService {
  static const _klrBase = 'https://indialotteryapi.com/wp-json/klr/v1';

  static const List<String> kTodayDrawCodes = [
    'DEAR1',
    'LSK3',
    'DEAR6',
    'DEAR8',
  ];

  /// YouTube live 1st prize — start fast polling from these times (IST).
  static const Map<String, (int hour, int minute)> kLivePublishStart = {
    'DEAR1': (13, 1), // 1:01 PM
    'LSK3': (15, 1), // 3:01 PM Kerala
    'DEAR6': (18, 1), // 6:01 PM
    'DEAR8': (20, 1), // 8:01 PM
  };

  /// Full result board (all prizes + compliments) — target publish times.
  static const Map<String, (int hour, int minute)> kFullResultTarget = {
    'DEAR1': (13, 10), // 1:10 PM
    'LSK3': (15, 10), // 3:10 PM
    'DEAR6': (18, 10), // 6:10 PM
    'DEAR8': (20, 10), // 8:10 PM
  };

  static const Duration kLiveWindowAfterStart = Duration(minutes: 50);
  static const Duration kFullResultPushWindow = Duration(minutes: 30);
  static const Duration kFullResultPollInterval = Duration(seconds: 2);
  static const Duration kLivePollInterval = Duration(seconds: 3);
  static const Duration kTodayPollInterval = Duration(seconds: 15);
  static const Duration kIdlePollInterval = Duration(seconds: 30);

  static String _dateParam(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static bool isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime? _parseApiDay(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static int _minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

  static int _liveStartMinutes(String drawCode) {
    final start = kLivePublishStart[drawCode.trim().toUpperCase()];
    if (start == null) return 0;
    return start.$1 * 60 + start.$2;
  }

  static int _fullTargetMinutes(String drawCode) {
    final target = kFullResultTarget[drawCode.trim().toUpperCase()];
    if (target == null) return 0;
    return target.$1 * 60 + target.$2;
  }

  static DateTime? _scheduleTime(
    Map<String, (int hour, int minute)> map,
    String drawCode,
    DateTime at,
  ) {
    final slot = map[drawCode.trim().toUpperCase()];
    if (slot == null) return null;
    return DateTime(at.year, at.month, at.day, slot.$1, slot.$2);
  }

  /// True from live publish time (e.g. 1:01 PM) until window ends.
  static bool isInLiveWindow(String drawCode, DateTime at) {
    final startAt = _scheduleTime(kLivePublishStart, drawCode, at);
    if (startAt == null) return false;
    final endAt = startAt.add(kLiveWindowAfterStart);
    return !at.isBefore(startAt) && at.isBefore(endAt);
  }

  /// True from full-result target (e.g. 1:10 PM) until push window ends.
  static bool isInFullResultPush(String drawCode, DateTime at) {
    final targetAt = _scheduleTime(kFullResultTarget, drawCode, at);
    if (targetAt == null) return false;
    final endAt = targetAt.add(kFullResultPushWindow);
    return !at.isBefore(targetAt) && at.isBefore(endAt);
  }

  static bool isAtOrAfterFullTarget(String drawCode, DateTime at) {
    return _minutesOfDay(at) >= _fullTargetMinutes(drawCode);
  }

  /// True from live publish time (e.g. 8:01 PM) onward for that draw.
  static bool isAtOrAfterLiveStart(String drawCode, DateTime at) {
    return _minutesOfDay(at) >= _liveStartMinutes(drawCode);
  }

  static bool isAnyFullResultPushActive(DateTime at) {
    for (final code in kTodayDrawCodes) {
      if (isInFullResultPush(code, at)) return true;
    }
    return false;
  }

  static bool isAnyLiveWindowActive(DateTime at) {
    for (final code in kTodayDrawCodes) {
      if (isInLiveWindow(code, at)) return true;
    }
    return false;
  }

  static Duration pollIntervalFor(String drawCode, DateTime at) {
    if (isInFullResultPush(drawCode, at) || isAnyFullResultPushActive(at)) {
      return kFullResultPollInterval;
    }
    if (isInLiveWindow(drawCode, at) || isAnyLiveWindowActive(at)) {
      return kLivePollInterval;
    }
    final today = DateTime(at.year, at.month, at.day);
    if (isSameCalendarDay(today, at)) {
      return kTodayPollInterval;
    }
    return kIdlePollInterval;
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static bool _isValidCell(String v) {
    final t = v.trim();
    return t.isNotEmpty && t != '---';
  }

  static String _last3(String token) {
    final d = _digitsOnly(token);
    if (d.isEmpty) return '---';
    if (d.length <= 3) return d.padLeft(3, '0');
    return d.substring(d.length - 3);
  }

  static String _keralaFirstPrize(Map<String, dynamic>? first) {
    if (first == null) return '---';
    return _last3(first['ticket']?.toString() ?? '');
  }

  static List<String> _sortedCompliments(List<String> raw) {
    final numbers = <int>[];
    for (final item in raw) {
      if (!_isValidCell(item)) continue;
      final d = _digitsOnly(item);
      if (d.isEmpty) continue;
      final n = int.tryParse(d.length > 3 ? d.substring(d.length - 3) : d);
      if (n != null) numbers.add(n);
    }
    numbers.sort();
    final out = List<String>.filled(30, '---');
    for (var i = 0; i < numbers.length && i < 30; i++) {
      out[i] = numbers[i].toString().padLeft(3, '0');
    }
    return out;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  static Duration _httpTimeout(DateTime at) {
    return isAnyLiveWindowActive(at)
        ? const Duration(seconds: 8)
        : const Duration(seconds: 20);
  }

  static FetchedResultData? _parseKeralaJson(
    DateTime expectedDay,
    Map json,
  ) {
    final apiDay = _parseApiDay(json['date']);
    if (apiDay == null || !isSameCalendarDay(apiDay, expectedDay)) {
      return null;
    }
    final prizesRaw = json['prizes'];
    if (prizesRaw is! Map) return null;
    final p = Map<String, dynamic>.from(prizesRaw);
    final first = Map<String, dynamic>.from(
      json['first'] is Map ? json['first'] as Map : const {},
    );

    final firstPrize = _keralaFirstPrize(first);
    if (!_isValidCell(firstPrize)) return null;

    final second = _stringList(p['2nd']);
    final third = _stringList(p['3rd']);
    final fourth = _stringList(p['4th']);
    final fifth = _stringList(p['5th']);
    final ninth = _stringList(p['9th']);

    final prizes = [
      firstPrize,
      second.isNotEmpty ? _last3(second.first) : '---',
      third.isNotEmpty ? _last3(third.first) : '---',
      fourth.isNotEmpty ? _last3(fourth.first) : '---',
      fifth.isNotEmpty ? _last3(fifth.first) : '---',
    ];

    final complimentSource =
        ninth.isNotEmpty ? ninth : _stringList(p['8th']);
    final compliments = _sortedCompliments(
      complimentSource.take(30).map(_last3).toList(),
    );

    return FetchedResultData(
      drawCode: 'LSK3',
      date: expectedDay,
      prizes: prizes,
      compliments: compliments,
    );
  }

  static Future<FetchedResultData?> fetchKeralaLatest(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final uri = Uri.parse('$_klrBase/latest');
    try {
      final res = await http.get(uri).timeout(_httpTimeout(DateTime.now()));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! Map) return null;
      return _parseKeralaJson(day, Map<String, dynamic>.from(json));
    } catch (e) {
      debugPrint('fetchKeralaLatest: $e');
      return null;
    }
  }

  static Future<FetchedResultData?> fetchKerala(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final uri = Uri.parse('$_klrBase/by-date?date=${_dateParam(day)}');
    try {
      final res = await http.get(uri).timeout(_httpTimeout(DateTime.now()));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! Map) return null;
      return _parseKeralaJson(day, Map<String, dynamic>.from(json));
    } catch (e) {
      debugPrint('fetchKerala: $e');
      return null;
    }
  }

  /// DEAR today: [dear-lottery.in] chart must be live, then official PDF parse.
  static Future<FetchedResultData?> _fetchDearToday(
    String drawCode,
    DateTime day,
    DateTime now,
  ) async {
    return DearLotteryInSource.fetch(drawCode, day, now: now);
  }

  /// True when dear-lottery.in has uploaded today's chart for this draw.
  static Future<bool> todayDearPublishedOnWeb(
    String drawCode,
    DateTime day,
  ) async {
    final code = drawCode.trim().toUpperCase();
    if (!const {'DEAR1', 'DEAR6', 'DEAR8'}.contains(code)) return false;
    return DearLotteryInSource.hasPublishedChart(code, day);
  }

  static Future<FetchedResultData?> fetchDear(
    String drawCode,
    DateTime date,
  ) async {
    final day = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final isToday = isSameCalendarDay(day, now);
    final isYesterday = isSameCalendarDay(
      day,
      now.subtract(const Duration(days: 1)),
    );
    return DearLotteryInSource.fetch(
      drawCode,
      day,
      now: now,
      requirePublishedChart: isToday || isYesterday,
    );
  }

  static Future<FetchedResultData?> fetchDraw(
    String drawCode,
    DateTime date,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final day = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final isToday = isSameCalendarDay(day, now);
    if (!isToday) {
      if (code == 'LSK3') return fetchKerala(day);
      if (const {'DEAR1', 'DEAR6', 'DEAR8'}.contains(code)) {
        return fetchDear(code, day);
      }
      return null;
    }

    final afterFullTarget = isAtOrAfterFullTarget(code, now);
    final afterLiveStart = _minutesOfDay(now) >= _liveStartMinutes(code);

    if (code == 'LSK3') {
      if (afterFullTarget) {
        final full = await fetchKerala(day);
        if (full != null) return full;
        return fetchKeralaLatest(day);
      }
      if (afterLiveStart) {
        final latest = await fetchKeralaLatest(day);
        if (latest != null) return latest;
      }
      return fetchKerala(day);
    }
    if (const {'DEAR1', 'DEAR6', 'DEAR8'}.contains(code)) {
      return _fetchDearToday(code, day, now);
    }
    return null;
  }
}
