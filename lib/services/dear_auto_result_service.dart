import 'package:flutter/foundation.dart';

import 'result_fetch_service.dart';

/// Dear hybrid auto: admin manual 1st prize, website auto 2nd–5th + compliments.
class DearAutoResultService {
  DearAutoResultService._();
  static final DearAutoResultService instance = DearAutoResultService._();

  static const Set<String> dearDrawCodes = {'DEAR1', 'DEAR6', 'DEAR8'};

  static const Map<String, int> _autoCheckHourIst = {
    'DEAR1': 13,
    'DEAR6': 18,
    'DEAR8': 20,
  };

  static bool isDearDraw(String drawCode) =>
      dearDrawCodes.contains(drawCode.trim().toUpperCase());

  /// Current clock in India (IST), independent of device timezone.
  static DateTime nowInIndia({DateTime? at}) {
    final ist = (at ?? DateTime.now())
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
  }

  /// Dear auto fetch allowed after 1 PM / 6 PM / 8 PM IST on draw day.
  static bool isAtOrAfterAutoCheck(String drawCode, {DateTime? at}) {
    final code = drawCode.trim().toUpperCase();
    final hour = _autoCheckHourIst[code];
    if (hour == null) return false;
    final ist = nowInIndia(at: at);
    return ist.hour > hour || (ist.hour == hour && ist.minute >= 0);
  }

  static bool _isValidCell(String v) {
    final t = v.trim();
    return t.isNotEmpty && t != '---';
  }

  static bool autoSectionsComplete(List<String> prizes, List<String> compliments) {
    if (prizes.length < 5) return false;
    for (var i = 1; i < 5; i++) {
      if (!_isValidCell(prizes[i])) return false;
    }
    return compliments.any(_isValidCell);
  }

  static String _resolveAutoStatus({
    required bool manualFirstPrize,
    required List<String> prizes,
    required List<String> compliments,
    required bool fetchedFromWeb,
    required bool fetchAttempted,
  }) {
    if (autoSectionsComplete(prizes, compliments)) return 'completed';
    if (manualFirstPrize) {
      if (!fetchAttempted) return 'waiting_for_auto_sections';
      return fetchedFromWeb ? 'waiting_for_auto_sections' : 'pending';
    }
    return 'pending';
  }

  /// Merge website/cloud numbers into an existing Dear snapshot.
  /// Manual 1st prize is never overwritten; only 2nd–5th + compliments fill from auto.
  static DearHybridMergeResult mergeHybrid({
    required List<String> existingPrizes,
    required List<String> existingCompliments,
    required bool manualFirstPrize,
    required List<String> incomingPrizes,
    required List<String> incomingCompliments,
    required bool fetchedFromWeb,
    bool fetchAttempted = true,
  }) {
    final prizes = List<String>.filled(5, '---');
    for (var i = 0; i < 5; i++) {
      final ex = i < existingPrizes.length ? existingPrizes[i] : '---';
      final inc = i < incomingPrizes.length ? incomingPrizes[i] : '---';
      if (i == 0 && manualFirstPrize && _isValidCell(ex)) {
        prizes[i] = ex;
      } else {
        prizes[i] = _isValidCell(inc) ? inc : (_isValidCell(ex) ? ex : '---');
      }
    }

    final compliments = List<String>.filled(30, '---');
    for (var i = 0; i < 30; i++) {
      final ex =
          i < existingCompliments.length ? existingCompliments[i] : '---';
      final inc =
          i < incomingCompliments.length ? incomingCompliments[i] : '---';
      compliments[i] = _isValidCell(inc) ? inc : (_isValidCell(ex) ? ex : '---');
    }

    final source = <String, String>{};
    if (manualFirstPrize && _isValidCell(prizes[0])) {
      source['firstPrize'] = 'manual';
    }
    if (autoSectionsComplete(prizes, compliments)) {
      source['otherPrizes'] = 'auto';
    }

    final autoStatus = _resolveAutoStatus(
      manualFirstPrize: manualFirstPrize,
      prizes: prizes,
      compliments: compliments,
      fetchedFromWeb: fetchedFromWeb,
      fetchAttempted: fetchAttempted,
    );

    return DearHybridMergeResult(
      prizes: prizes,
      compliments: compliments,
      autoStatus: autoStatus,
      source: source,
    );
  }

  /// Fetch Dear website result and merge into hybrid fields (does not save).
  Future<DearHybridMergeResult?> fetchAndMerge({
    required String drawCode,
    required DateTime day,
    required List<String> existingPrizes,
    required List<String> existingCompliments,
    required bool manualFirstPrize,
    DateTime? at,
  }) async {
    final code = drawCode.trim().toUpperCase();
    if (!isDearDraw(code)) return null;

    final calendarDay = DateTime(day.year, day.month, day.day);
    final istNow = nowInIndia(at: at);
    final isToday = ResultFetchService.isSameCalendarDay(calendarDay, istNow);

    debugPrint('DEAR_AUTO_START draw=$code date=$calendarDay manual=$manualFirstPrize');

    if (isToday && !isAtOrAfterAutoCheck(code, at: istNow)) {
      debugPrint('DEAR_AUTO_NO_DATA draw=$code reason=before_auto_check_ist');
      return mergeHybrid(
        existingPrizes: existingPrizes,
        existingCompliments: existingCompliments,
        manualFirstPrize: manualFirstPrize,
        incomingPrizes: const [],
        incomingCompliments: const [],
        fetchedFromWeb: false,
        fetchAttempted: false,
      );
    }

    try {
      final fetched = await ResultFetchService.fetchDraw(code, calendarDay);
      if (fetched == null) {
        debugPrint('DEAR_AUTO_NO_DATA draw=$code date=$calendarDay');
        return mergeHybrid(
          existingPrizes: existingPrizes,
          existingCompliments: existingCompliments,
          manualFirstPrize: manualFirstPrize,
          incomingPrizes: const [],
          incomingCompliments: const [],
          fetchedFromWeb: false,
          fetchAttempted: true,
        );
      }

      debugPrint('DEAR_AUTO_FETCH_SUCCESS draw=$code date=$calendarDay');
      return mergeHybrid(
        existingPrizes: existingPrizes,
        existingCompliments: existingCompliments,
        manualFirstPrize: manualFirstPrize,
        incomingPrizes: fetched.prizes,
        incomingCompliments: fetched.compliments,
        fetchedFromWeb: true,
        fetchAttempted: true,
      );
    } catch (e, st) {
      debugPrint('DEAR_AUTO_ERROR draw=$code error=$e\n$st');
      return mergeHybrid(
        existingPrizes: existingPrizes,
        existingCompliments: existingCompliments,
        manualFirstPrize: manualFirstPrize,
        incomingPrizes: const [],
        incomingCompliments: const [],
        fetchedFromWeb: false,
        fetchAttempted: true,
      );
    }
  }
}

class DearHybridMergeResult {
  final List<String> prizes;
  final List<String> compliments;
  final String autoStatus;
  final Map<String, String> source;

  const DearHybridMergeResult({
    required this.prizes,
    required this.compliments,
    required this.autoStatus,
    required this.source,
  });
}
