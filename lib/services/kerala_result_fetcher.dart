import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../kerala_compliment_rules.dart';
import 'fetched_result_data.dart';

class KeralaParsedResult {
  final DateTime date;
  final List<String> prizes;
  final List<String> compliments;
  final int? declaredNinthCount;
  final int ninthScrapedCount;
  final bool ninthComplete;
  final bool complimentsValid;

  const KeralaParsedResult({
    required this.date,
    required this.prizes,
    required this.compliments,
    this.declaredNinthCount,
    this.ninthScrapedCount = 0,
    this.ninthComplete = false,
    this.complimentsValid = false,
  });
}

class KeralaResultFetcher {
  static const _base = 'https://www.keralalotteries.net';

  static String _dateDmy(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  static String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ');

  static String? _section(String html, String startLabel, List<String> endLabels) {
    final lower = html.toLowerCase();
    final start = lower.indexOf(startLabel.toLowerCase());
    if (start < 0) return null;
    var end = html.length;
    for (final label in endLabels) {
      final i = lower.indexOf(label.toLowerCase(), start + startLabel.length);
      if (i > start && i < end) end = i;
    }
    return html.substring(start, end);
  }

  static List<String> _fourDigitsFromText(String text) {
    return RegExp(r'\b(\d{4})\b')
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toList();
  }

  static String _last3(String token) {
    final d = token.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '---';
    if (d.length <= 3) return d.padLeft(3, '0');
    return d.substring(d.length - 3);
  }

  static bool _isValidCell(String v) {
    final t = v.trim();
    return t.isNotEmpty && t != '---';
  }

  static String? _seriesTicket(String section) {
    final match = RegExp(
      r'\b([A-Z]{2})\s+(\d{6})\b',
      caseSensitive: false,
    ).firstMatch(_stripTags(section));
    if (match == null) return null;
    return match.group(2);
  }

  static String? _firstFourDigit(String section) {
    final nums = KeralaComplimentRules.filterNinthGridNumbers(
      _fourDigitsFromText(_stripTags(section)),
    );
    if (nums.isEmpty) return null;
    return _last3(nums.first);
  }

  @visibleForTesting
  static KeralaParsedResult? parseHtml(String html, DateTime expectedDay) {
    final day = DateTime(expectedDay.year, expectedDay.month, expectedDay.day);
    final dmy = _dateDmy(day);
    if (!html.contains(dmy) && !html.contains('${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}')) {
      return null;
    }

    final firstSec = _section(html, '1st Prize', ['Consolation Prize', '2nd Prize']) ?? '';
    final secondSec = _section(html, '2nd Prize', ['3rd Prize']) ?? '';
    final thirdSec = _section(html, '3rd Prize', ['4th Prize']) ?? '';
    final fourthSec = _section(html, '4th Prize', ['5th Prize']) ?? '';
    final fifthSec = _section(html, '5th Prize', ['6th Prize']) ?? '';
    final ninthSec = _section(
          html,
          '9th Prize',
          [
            'Repeated Draw Numbers',
            'Repeated Numbers in 9th',
            'Tomorrow draw',
            'SK ',
            'BT ',
          ],
        ) ??
        '';

    final prizes = List<String>.filled(5, '---');
    final first = _seriesTicket(firstSec);
    if (first != null) prizes[0] = _last3(first);
    final second = _seriesTicket(secondSec);
    if (second != null) prizes[1] = _last3(second);
    final third = _seriesTicket(thirdSec);
    if (third != null) prizes[2] = _last3(third);
    final fourth = _firstFourDigit(fourthSec);
    if (fourth != null) prizes[3] = fourth;
    final fifth = _firstFourDigit(fifthSec);
    if (fifth != null) prizes[4] = fifth;

    final declared = KeralaComplimentRules.parseDeclaredNinthCount(
      _stripTags(ninthSec),
    );
    final ninthFlat = KeralaComplimentRules.filterNinthGridNumbers(
      _fourDigitsFromText(_stripTags(ninthSec)),
    );
    final ninthComplete = KeralaComplimentRules.ninthIsComplete(
      ninthFlat,
      declared,
    );

    List<String> compliments = List<String>.filled(
      KeralaComplimentRules.complimentCount,
      '---',
    );
    var complimentsValid = false;
    if (ninthComplete) {
      compliments = KeralaComplimentRules.extractFromFlatNineGrid(ninthFlat);
      complimentsValid = KeralaComplimentRules.complimentsLookValid(compliments);
    }

    return KeralaParsedResult(
      date: day,
      prizes: prizes,
      compliments: compliments,
      declaredNinthCount: declared,
      ninthScrapedCount: ninthFlat.length,
      ninthComplete: ninthComplete,
      complimentsValid: complimentsValid,
    );
  }

  static Future<KeralaParsedResult?> fetch(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final dmy = _dateDmy(day);
    try {
      final home = await http.get(Uri.parse('$_base/')).timeout(
            const Duration(seconds: 20),
          );
      if (home.statusCode == 200) {
        final direct = RegExp(
          'href="(https://www\\.keralalotteries\\.net/[^"]*$dmy[^"]*\\.html)"',
          caseSensitive: false,
        ).firstMatch(home.body);
        final href = direct?.group(1);
        if (href != null) {
          final page = await http.get(Uri.parse(href)).timeout(
                const Duration(seconds: 20),
              );
          if (page.statusCode == 200) {
            final parsed = parseHtml(page.body, day);
            if (parsed != null) return parsed;
          }
        }
        final parsedHome = parseHtml(home.body, day);
        if (parsedHome != null) return parsedHome;
      }
    } catch (e) {
      debugPrint('KeralaResultFetcher.fetch home: $e');
    }

    final urls = [
      '$_base/search?q=$dmy',
    ];
    for (final url in urls) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(
              const Duration(seconds: 20),
            );
        if (res.statusCode != 200) continue;
        final parsed = parseHtml(res.body, day);
        if (parsed != null) return parsed;
      } catch (e) {
        debugPrint('KeralaResultFetcher.fetch $url: $e');
      }
    }
    return null;
  }

  static FetchedResultData? toFetchedData(KeralaParsedResult? parsed) {
    if (parsed == null) return null;
    if (!_isValidCell(parsed.prizes[0])) return null;
    return FetchedResultData(
      drawCode: 'LSK3',
      date: parsed.date,
      prizes: parsed.prizes,
      compliments: parsed.compliments,
    );
  }

  static bool complimentsLookValid(Iterable<String> raw) =>
      KeralaComplimentRules.complimentsLookValid(raw);

  static bool ninthPrizeIsComplete(KeralaParsedResult parsed) =>
      parsed.ninthComplete;
}

typedef KeralaSaveFn = Future<void> Function(FetchedResultData data);

class KeralaAutoResultService {
  KeralaAutoResultService._();
  static final KeralaAutoResultService instance = KeralaAutoResultService._();

  static const _stableWatch = Duration(minutes: 1);

  List<String>? _watchingCompliments;
  DateTime? _watchStartedAt;
  String _statusMessage = '';

  String get statusMessage => _statusMessage;

  void resetWatch() {
    _watchingCompliments = null;
    _watchStartedAt = null;
  }

  bool _ninthWatchAllowsComplimentSave(
    List<String> candidate, {
    required bool userTriggered,
  }) {
    if (!KeralaResultFetcher.complimentsLookValid(candidate)) return false;
    if (userTriggered) return true;

    final key = candidate.join(',');
    final prev = _watchingCompliments?.join(',');
    if (prev != key) {
      _watchingCompliments = List<String>.from(candidate);
      _watchStartedAt = DateTime.now();
      _statusMessage = '9th full — numbers change aayi, 1 min watch restart...';
      return false;
    }
    final started = _watchStartedAt;
    if (started == null) {
      _watchStartedAt = DateTime.now();
      _statusMessage = '9th prize full — 1 min watch...';
      return false;
    }
    if (DateTime.now().difference(started) < _stableWatch) {
      _statusMessage =
          '9th prize ${_watchingCompliments?.where(KeralaComplimentRules.isValidComplimentCell).length ?? 0}/30 — full aakumpol 1 min watch';
      return false;
    }
    _statusMessage = '9th full 1 min stable — compliments save cheyyunnu...';
    return true;
  }

  Future<bool> tick(
    DateTime date, {
    required KeralaSaveFn onSave,
    bool userTriggered = false,
  }) async {
    final parsed = await KeralaResultFetcher.fetch(date);
    if (parsed == null) return false;

    if (!parsed.ninthComplete) {
      resetWatch();
      if (parsed.declaredNinthCount != null) {
        _statusMessage =
            '9th prize ${parsed.ninthScrapedCount}/${parsed.declaredNinthCount} — full aakumpol 1 min watch';
      }
    }

    final fetched = KeralaResultFetcher.toFetchedData(parsed);
    if (fetched == null) return false;

    var saveCompliments = false;
    if (parsed.ninthComplete && parsed.complimentsValid) {
      saveCompliments = _ninthWatchAllowsComplimentSave(
        fetched.compliments,
        userTriggered: userTriggered,
      );
    } else {
      resetWatch();
    }

    if (!saveCompliments) {
      final partial = FetchedResultData(
        drawCode: 'LSK3',
        date: fetched.date,
        prizes: fetched.prizes,
        compliments: List<String>.filled(
          KeralaComplimentRules.complimentCount,
          '---',
        ),
      );
      final hasPrize = partial.prizes.any(_isValidCell);
      if (!hasPrize) return false;
      await onSave(partial);
      return true;
    }

    await onSave(fetched);
    resetWatch();
    return true;
  }

  static bool _isValidCell(String v) {
    final t = v.trim();
    return t.isNotEmpty && t != '---';
  }
}
