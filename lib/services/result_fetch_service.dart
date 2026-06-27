import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'dear_fast_result_source.dart';
import 'dear_lottery_in_source.dart';
import 'fetched_result_data.dart';
import 'ist_clock.dart';
import '../kerala_compliment_rules.dart';

export 'fetched_result_data.dart';

class ResultFetchService {
  static const _klrBase = 'https://indialotteryapi.com/wp-json/klr/v1';
  static const _dearApiBase =
      'https://indialotteryapi.com/wp-json/dearlottery/v1';

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

  static DateTime? _parseKeralaApiDay(Map json) {
    for (final key in ['date', 'draw_date', 'result_date']) {
      final d = _parseApiDay(json[key]);
      if (d != null) return d;
    }
    return null;
  }

  static List<String> _keralaComplimentsFromApi(Map<String, dynamic> prizes) {
    final empty = List<String>.filled(
      KeralaComplimentRules.complimentCount,
      '---',
    );
    final ninthRaw = _stringList(prizes['9th']);
    if (ninthRaw.isEmpty) return empty;
    final ninthFlat = KeralaComplimentRules.filterNinthGridNumbers(ninthRaw);
    if (ninthFlat.isEmpty) return empty;

    final declared = ninthFlat.length >= 144 ? 144 : ninthFlat.length;
    if (!KeralaComplimentRules.ninthIsComplete(ninthFlat, declared)) {
      return empty;
    }
    final extracted = KeralaComplimentRules.extractFromFlatNineGrid(ninthFlat);
    if (KeralaComplimentRules.complimentsLookValid(extracted)) {
      return extracted;
    }
    return empty;
  }

  @visibleForTesting
  static FetchedResultData? parseKeralaApiJson(
    DateTime expectedDay,
    Map<String, dynamic> json,
  ) {
    return _parseKeralaJson(expectedDay, json);
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
  static bool isAtOrAfterLiveStart(String drawCode, DateTime at) {
    final ist = IstClock.now(at: at);
    return _minutesOfDay(ist) >= _liveStartMinutes(drawCode);
  }

  static bool isInLiveWindow(String drawCode, DateTime at) {
    final ist = IstClock.now(at: at);
    final startAt = _scheduleTime(kLivePublishStart, drawCode, ist);
    if (startAt == null) return false;
    final endAt = startAt.add(kLiveWindowAfterStart);
    return !ist.isBefore(startAt) && ist.isBefore(endAt);
  }

  static bool isInFullResultPush(String drawCode, DateTime at) {
    final ist = IstClock.now(at: at);
    final targetAt = _scheduleTime(kFullResultTarget, drawCode, ist);
    if (targetAt == null) return false;
    final endAt = targetAt.add(kFullResultPushWindow);
    return !ist.isBefore(targetAt) && ist.isBefore(endAt);
  }

  static bool isAtOrAfterFullTarget(String drawCode, DateTime at) {
    final ist = IstClock.now(at: at);
    return _minutesOfDay(ist) >= _fullTargetMinutes(drawCode);
  }

  static bool isAnyFullResultPushActive(DateTime at) {
    final ist = IstClock.now(at: at);
    for (final code in kTodayDrawCodes) {
      if (isInFullResultPush(code, ist)) return true;
    }
    return false;
  }

  static bool isAnyLiveWindowActive(DateTime at) {
    final ist = IstClock.now(at: at);
    for (final code in kTodayDrawCodes) {
      if (isInLiveWindow(code, ist)) return true;
    }
    return false;
  }

  static Duration pollIntervalFor(String drawCode, DateTime at) {
    final ist = IstClock.now(at: at);
    if (isInFullResultPush(drawCode, ist) || isAnyFullResultPushActive(ist)) {
      return kFullResultPollInterval;
    }
    if (isInLiveWindow(drawCode, ist) || isAnyLiveWindowActive(ist)) {
      return kLivePollInterval;
    }
    final today = IstClock.calendarDay(at: ist);
    if (isSameCalendarDay(today, ist)) {
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
    final apiDay = _parseKeralaApiDay(Map<String, dynamic>.from(json));
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

    final prizes = [
      firstPrize,
      second.isNotEmpty ? _last3(second.first) : '---',
      third.isNotEmpty ? _last3(third.first) : '---',
      fourth.isNotEmpty ? _last3(fourth.first) : '---',
      fifth.isNotEmpty ? _last3(fifth.first) : '---',
    ];

    final compliments = _keralaComplimentsFromApi(p);

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

  static String? _dearApiTimeSlot(String drawCode) {
    switch (drawCode.trim().toUpperCase()) {
      case 'DEAR1':
        return '1pm';
      case 'DEAR6':
        return '6pm';
      case 'DEAR8':
        return '8pm';
      default:
        return null;
    }
  }

  static String _dearFirstPrize(List<String> firstList) {
    for (final token in firstList.reversed) {
      final d = _digitsOnly(token);
      if (d.length >= 3) return _last3(token);
    }
    if (firstList.isNotEmpty) return _last3(firstList.first);
    return '---';
  }

  static String _dearFifthPrizeDisplay(
    List<String> fourth,
    List<String> fifth,
  ) {
    if (fourth.length >= 2) return _last3(fourth[1]);
    if (fifth.isNotEmpty) return _last3(fifth.first);
    return '---';
  }

  @visibleForTesting
  static FetchedResultData? parseDearApiJson(
    String drawCode,
    DateTime expectedDay,
    Map<String, dynamic> json,
  ) {
    return _parseDearApiJson(drawCode, expectedDay, json);
  }

  static FetchedResultData? _parseDearApiJson(
    String drawCode,
    DateTime expectedDay,
    Map<String, dynamic> json,
  ) {
    final apiDay = _parseApiDay(json['date']);
    if (apiDay == null || !isSameCalendarDay(apiDay, expectedDay)) {
      return null;
    }
    final expectedSlot = _dearApiTimeSlot(drawCode);
    final apiTime = json['time']?.toString().toLowerCase();
    if (expectedSlot != null &&
        apiTime != null &&
        apiTime.isNotEmpty &&
        apiTime != expectedSlot) {
      return null;
    }

    final prizesRaw = json['prizes'];
    if (prizesRaw is! Map) return null;
    final p = Map<String, dynamic>.from(prizesRaw);

    final firstList = _stringList(p['1st']);
    final firstPrize = _dearFirstPrize(firstList);
    if (!_isValidCell(firstPrize)) return null;

    final second = _stringList(p['2nd']);
    final third = _stringList(p['3rd']);
    final fourth = _stringList(p['4th']);
    final fifth = _stringList(p['5th']);
    final cons = _stringList(json['cons']);

    final prizes = [
      firstPrize,
      second.isNotEmpty ? _last3(second.first) : '---',
      third.isNotEmpty ? _last3(third.first) : '---',
      fourth.isNotEmpty ? _last3(fourth.first) : '---',
      _dearFifthPrizeDisplay(fourth, fifth),
    ];

    final complimentSource = fifth.isNotEmpty ? fifth : cons;
    final compliments = _sortedCompliments(
      complimentSource.map(_last3).toList(),
    );

    return FetchedResultData(
      drawCode: drawCode.trim().toUpperCase(),
      date: expectedDay,
      prizes: prizes,
      compliments: compliments,
    );
  }

  static Future<FetchedResultData?> fetchDearApi(
    String drawCode,
    DateTime date,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final slot = _dearApiTimeSlot(code);
    if (slot == null) return null;
    final day = DateTime(date.year, date.month, date.day);
    final timeout = _httpTimeout(IstClock.now());

    final uris = [
      Uri.parse('$_dearApiBase/by-date?date=${_dateParam(day)}&time=$slot'),
      Uri.parse(
        '$_dearApiBase/by-date?date=${_dateParam(day)}&time=$slot&fallback=1',
      ),
      Uri.parse('$_dearApiBase/latest?time=$slot'),
    ];

    for (final uri in uris) {
      try {
        final res = await http.get(uri).timeout(timeout);
        if (res.statusCode != 200) continue;
        final json = jsonDecode(res.body);
        if (json is! Map) continue;
        final parsed = _parseDearApiJson(
          code,
          day,
          Map<String, dynamic>.from(json),
        );
        if (parsed != null) return parsed;
      } catch (e) {
        debugPrint('fetchDearApi $code $uri: $e');
      }
    }
    return null;
  }

  static Future<FetchedResultData?> fetchKerala(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final urls = [
      '$_klrBase/by-date?date=${_dateParam(day)}',
      '$_klrBase/by-date?date=${_dateParam(day)}&fallback=1',
    ];
    for (final url in urls) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(_httpTimeout(DateTime.now()));
        if (res.statusCode != 200) continue;
        final json = jsonDecode(res.body);
        if (json is! Map) continue;
        final parsed = _parseKeralaJson(day, Map<String, dynamic>.from(json));
        if (parsed != null) return parsed;
      } catch (e) {
        debugPrint('fetchKerala $url: $e');
      }
    }
    return null;
  }

  /// DEAR: chart gate first, then direct PDF fallbacks (dear-lottery.in title often shows next day).
  static Future<FetchedResultData?> fetchDear(
    String drawCode,
    DateTime date,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final day = DateTime(date.year, date.month, date.day);
    final istNow = IstClock.now();
    final istToday = IstClock.calendarDay(at: istNow);
    final isToday = isSameCalendarDay(day, istToday);
    final isYesterday = isSameCalendarDay(
      day,
      istToday.subtract(const Duration(days: 1)),
    );

    FetchedResultData? best;

    best = await fetchDearApi(code, day);
    if (_dearFetchUseful(best)) {
      debugPrint('fetchDear $code: api');
      return best;
    }

    best = await DearFastResultSource.fetchDearLotteryDotInPdf(code, day);
    if (_dearFetchUseful(best)) {
      debugPrint('fetchDear $code: dearlottery-pdf');
      return best;
    }

    if (isToday || isYesterday) {
      best = await DearLotteryInSource.fetch(
        code,
        day,
        now: istNow,
        requirePublishedChart: true,
      );
      if (_dearFetchUseful(best)) {
        debugPrint('fetchDear $code: chart+pdf');
        return best;
      }
    }

    best = await DearFastResultSource.fetchPdf(code, day);
    if (_dearFetchUseful(best)) {
      debugPrint('fetchDear $code: mirror-pdf');
      return best;
    }

    best = await DearLotteryInSource.fetch(
      code,
      day,
      now: istNow,
      requirePublishedChart: false,
    );
    if (_dearFetchUseful(best)) {
      debugPrint('fetchDear $code: nagaland-pdf');
      return best;
    }

    best = await DearFastResultSource.fetchHtml(code, day);
    if (_dearFetchUseful(best, allowFirstPrizeOnly: !isToday)) {
      debugPrint('fetchDear $code: html-first');
      return best;
    }

    debugPrint('fetchDear $code: no data for $day');
    return best;
  }

  static bool _dearFetchUseful(
    FetchedResultData? data, {
    bool allowFirstPrizeOnly = false,
  }) {
    if (data == null) return false;
    if (DearFastResultSource.hasFullResult(data)) return true;
    for (var i = 1; i < data.prizes.length; i++) {
      if (_isValidCell(data.prizes[i])) return true;
    }
    if (data.compliments.any(_isValidCell)) return true;
    return allowFirstPrizeOnly && _isValidCell(data.prizes[0]);
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

  static Future<FetchedResultData?> fetchDraw(
    String drawCode,
    DateTime date,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final day = DateTime(date.year, date.month, date.day);
    final istNow = IstClock.now();
    final istToday = IstClock.calendarDay(at: istNow);
    final isToday = isSameCalendarDay(day, istToday);
    if (!isToday) {
      if (code == 'LSK3') return fetchKerala(day);
      if (const {'DEAR1', 'DEAR6', 'DEAR8'}.contains(code)) {
        return fetchDear(code, day);
      }
      return null;
    }

    final afterFullTarget = isAtOrAfterFullTarget(code, istNow);
    final afterLiveStart = _minutesOfDay(istNow) >= _liveStartMinutes(code);

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
      return fetchDear(code, day);
    }
    return null;
  }
}
