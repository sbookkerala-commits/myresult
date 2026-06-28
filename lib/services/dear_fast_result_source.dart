import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'fetched_result_data.dart';

/// Fast Dear results from [keralalottery.info] — PDF uploads before JSON API.
class DearFastResultSource {
  static const _base = 'https://www.keralalottery.info';
  static const _htmlPaths = [
    '/dear-lottery-result',
    '/dear-jackpot-result-chart',
  ];

  static String? _pdfFileCode(String drawCode) {
    switch (drawCode.trim().toUpperCase()) {
      case 'DEAR1':
        return 'MN';
      case 'DEAR6':
        return 'DN';
      case 'DEAR8':
        return 'EN';
      default:
        return null;
    }
  }

  static int? _htmlColumnIndex(String drawCode) {
    switch (drawCode.trim().toUpperCase()) {
      case 'DEAR1':
        return 1;
      case 'DEAR6':
        return 2;
      case 'DEAR8':
        return 3;
      default:
        return null;
    }
  }

  static String _dateIso(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String _dateDmy(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
  }

  static String _last3(String token) {
    final d = token.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '---';
    if (d.length <= 3) return d.padLeft(3, '0');
    return d.substring(d.length - 3);
  }

  /// Result board: 5th row = 2nd number from 4th-tier block (matches API layout).
  static String _dearFifthPrizeDisplay(
    List<String> fourthNums,
    List<String> fifthRaw,
  ) {
    if (fourthNums.length >= 2) return _last3(fourthNums[1]);
    if (fifthRaw.isNotEmpty) return _last3(fifthRaw.first);
    return '---';
  }

  static bool _isValidCell(String v) {
    final t = v.trim();
    return t.isNotEmpty && t != '---';
  }

  static List<String> _emptyPrizes() => List<String>.filled(5, '---');

  static List<String> _emptyCompliments() => List<String>.filled(30, '---');

  /// Old PDF: long digit lines before Sold by. New PDF (Jun 2026+): 100×4-digit
  /// 5th-prize lines — compliments = first 30 only, not all 100 sorted.
  static List<String> dearComplimentSourceNumbers(
    List<String> raw, {
    required bool fromLongGrid,
  }) {
    if (raw.isEmpty) return const [];
    if (fromLongGrid || raw.length <= 30) return raw;
    return raw.take(30).toList();
  }

  static List<String> complimentsFromNumbers(
    List<String> raw, {
    required bool fromLongGrid,
  }) {
    final source = dearComplimentSourceNumbers(raw, fromLongGrid: fromLongGrid);
    if (source.isEmpty) return _emptyCompliments();
    return _sortedCompliments(source.map(_last3).toList());
  }

  /// API `prizes.5th` — first 30 published numbers → 30 compliment cells.
  static List<String> complimentsFromApiFifth(List<String> fifth) {
    if (fifth.isEmpty) return _emptyCompliments();
    return complimentsFromNumbers(fifth, fromLongGrid: false);
  }

  static FetchedResultData _partialFirstPrize(
    String drawCode,
    DateTime day,
    String firstPrize,
  ) {
    final prizes = _emptyPrizes();
    prizes[0] = firstPrize;
    return FetchedResultData(
      drawCode: drawCode.trim().toUpperCase(),
      date: DateTime(day.year, day.month, day.day),
      prizes: prizes,
      compliments: _emptyCompliments(),
    );
  }

  /// HTML table on keralalottery.info — fastest for 1st prize.
  static Future<FetchedResultData?> fetchHtml(
    String drawCode,
    DateTime date,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final col = _htmlColumnIndex(code);
    if (col == null) return null;
    final day = DateTime(date.year, date.month, date.day);
    final iso = _dateIso(day);
    final dmy = _dateDmy(day);

    for (final path in _htmlPaths) {
      try {
        final res = await http
            .get(Uri.parse('$_base$path'))
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) continue;
        final html = res.body;
        final row = _findHistoryRow(html, iso, dmy);
        if (row == null) continue;
        final cell = _cellAt(row, col);
        if (cell == null || cell.contains('=====')) continue;
        final first = _parseHtmlFirstPrize(cell);
        if (!_isValidCell(first)) continue;
        return _partialFirstPrize(code, day, first);
      } catch (e) {
        debugPrint('DearFastResultSource.fetchHtml $code: $e');
      }
    }
    return null;
  }

  static String? _findHistoryRow(String html, String iso, String dmy) {
    final byIso = RegExp(
      '<tr[^>]*>\\s*<td[^>]*>\\s*<time[^>]*datetime="$iso"[^>]*>.*?</tr>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (byIso != null) return byIso.group(0);

    final byDmy = RegExp(
      '<tr[^>]*>\\s*<td[^>]*>\\s*<time[^>]*>$dmy</time>.*?</tr>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    return byDmy?.group(0);
  }

  static String? _cellAt(String row, int columnIndex) {
    final cells = RegExp(r'<td[^>]*>(.*?)</td>', caseSensitive: false, dotAll: true)
        .allMatches(row)
        .map((m) => m.group(1) ?? '')
        .map((c) => c.replaceAll(RegExp(r'<[^>]+>'), '').trim())
        .toList();
    if (cells.length <= columnIndex) return null;
    return cells[columnIndex];
  }

  static String _parseHtmlFirstPrize(String cell) {
    final cleaned = cell.replaceAll(RegExp(r'\s+'), ' ').trim();
    final match = RegExp(r'(\d{4,5})\s*$').firstMatch(cleaned);
    if (match != null) return _last3(match.group(1)!);
    return _last3(cleaned);
  }

  /// Official-style PDF mirrored at keralalottery.info/images/{MN,DN,EN}.pdf
  static Future<FetchedResultData?> fetchPdf(
    String drawCode,
    DateTime date,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final fileCode = _pdfFileCode(code);
    if (fileCode == null) return null;
    final day = DateTime(date.year, date.month, date.day);

    try {
      final uri = Uri.parse('$_base/images/$fileCode.pdf');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.length < 4096) return null;
      final text = _extractPdfText(res.bodyBytes);
      if (text.trim().isEmpty) return null;
      return _parseDearPdfText(code, day, text);
    } catch (e) {
      debugPrint('DearFastResultSource.fetchPdf $code: $e');
      return null;
    }
  }

  static String _extractPdfText(List<int> bytes) {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      return PdfTextExtractor(document).extractText();
    } finally {
      document?.dispose();
    }
  }

  @visibleForTesting
  static FetchedResultData? parseDearPdfText(
    String drawCode,
    DateTime day,
    String text,
  ) =>
      _parseDearPdfText(drawCode, day, text);

  /// Parses official Nagaland Dear gazette text into app result rows.
  static FetchedResultData? parseOfficialPdfText(
    String drawCode,
    DateTime day,
    String text,
  ) =>
      _parseDearPdfText(drawCode, day, text);

  static DateTime? parsePdfDrawDate(String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty);
    for (final line in lines) {
      final slash = RegExp(r'^(\d{2})/(\d{2})/(\d{2})$').firstMatch(line);
      if (slash != null) {
        final day = int.parse(slash.group(1)!);
        final month = int.parse(slash.group(2)!);
        var year = int.parse(slash.group(3)!);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }
      final dash = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(line);
      if (dash != null) {
        return DateTime(
          int.parse(dash.group(3)!),
          int.parse(dash.group(2)!),
          int.parse(dash.group(1)!),
        );
      }
    }
    return null;
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static FetchedResultData? _parseDearPdfText(
    String drawCode,
    DateTime day,
    String rawText,
  ) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final pdfDay = parsePdfDrawDate(rawText);
    if (pdfDay == null || !_sameCalendarDay(pdfDay, day)) {
      debugPrint(
        'DearFastResultSource: PDF date mismatch for $drawCode '
        '(expected ${_dateIso(day)}, got ${pdfDay == null ? 'none' : _dateIso(pdfDay)})',
      );
      return null;
    }

    final joined = lines.join('\n');
    final firstMatch = RegExp(r'(\d{1,2}[A-Z])\s+(\d{5})').firstMatch(joined);
    if (firstMatch == null) return null;
    final firstPrize = _last3(firstMatch.group(2)!);

    final soldIdx = lines.indexWhere((l) => l.toLowerCase().contains('sold by'));
    if (soldIdx < 0) {
      return _parseDearPdfWithoutSoldBy(drawCode, day, lines, firstPrize);
    }

    final fifthRaw = <String>[];
    var fromLongGrid = false;
    for (var i = 0; i < soldIdx; i++) {
      final line = lines[i].replaceAll(RegExp(r'\s+'), '');
      if (RegExp(r'^\d{40,}$').hasMatch(line)) {
        fromLongGrid = true;
        for (var j = 0; j + 4 <= line.length; j += 4) {
          fifthRaw.add(line.substring(j, j + 4));
        }
      } else if (RegExp(r'^\d{4}$').hasMatch(line)) {
        fifthRaw.add(line);
      }
    }

    final afterSold = lines.sublist(soldIdx + 1);
    final fiveDigitLines = <String>[];
    final fourDigitLines = <String>[];
    var passedTdsBlock = false;

    for (final line in afterSold) {
      if (RegExp(r'(\d{1,2}[A-Z])\s+\d{5}').hasMatch(line)) break;
      if (line.contains('5thPrize')) break;
      if (RegExp(r'^\d{2}/\d{2}/\d{2}$').hasMatch(line)) {
        passedTdsBlock = true;
        continue;
      }
      if (line.toUpperCase().contains('TDS')) {
        passedTdsBlock = true;
        continue;
      }
      if (line.toUpperCase().contains('WEEKLY LOTTERY')) continue;
      if (RegExp(r'^\d{5}$').hasMatch(line.replaceAll(RegExp(r'\s+'), ''))) {
        continue;
      }

      final nums = RegExp(r'\d{4,5}')
          .allMatches(line)
          .map((m) => m.group(0)!)
          .toList();
      if (nums.isEmpty) continue;

      if (!passedTdsBlock && nums.every((n) => n.length == 5)) {
        fiveDigitLines.add(line);
      } else if (nums.every((n) => n.length == 4)) {
        fourDigitLines.add(line);
      }
    }

    final secondNums = _numbersFromLines(fiveDigitLines, 5);
    final thirdNums = _numbersFromLines(
      fourDigitLines.length >= 2 ? fourDigitLines.sublist(0, 2) : fourDigitLines,
      4,
    );
    final fourthLines = fourDigitLines.length > 2
        ? fourDigitLines.sublist(2)
        : <String>[];
    final fourthNums = _numbersFromLines(fourthLines, 4);

    return _buildDearPdfResult(
      drawCode: drawCode,
      day: day,
      firstPrize: firstPrize,
      secondNums: secondNums,
      thirdNums: thirdNums,
      fourthNums: fourthNums,
      fifthRaw: fifthRaw,
      complimentsFromLongGrid: fromLongGrid,
    );
  }

  /// dearlottery.in uploads — consolation grid first, prizes before series line.
  static FetchedResultData? _parseDearPdfWithoutSoldBy(
    String drawCode,
    DateTime day,
    List<String> lines,
    String firstPrize,
  ) {
    final firstLineIdx = lines.indexWhere(
      (l) => RegExp(r'(\d{1,2}[A-Z])\s+(\d{5})').hasMatch(l),
    );
    if (firstLineIdx < 0) {
      return _partialFirstPrize(drawCode, day, firstPrize);
    }

    final fifthRaw = <String>[];
    var fromLongGrid = false;
    final fiveDigitLines = <String>[];
    final fourDigitLines = <String>[];

    for (var i = 0; i < firstLineIdx; i++) {
      final rawLine = lines[i];
      final line = rawLine.replaceAll(RegExp(r'\s+'), '');
      if (RegExp(r'^\d{40,}$').hasMatch(line)) {
        fromLongGrid = true;
        for (var j = 0; j + 4 <= line.length; j += 4) {
          fifthRaw.add(line.substring(j, j + 4));
        }
        continue;
      }
      if (RegExp(r'^\d{4}$').hasMatch(line)) {
        fifthRaw.add(line);
        continue;
      }
      if (RegExp(r'^\d{2}/\d{2}/\d{2}$').hasMatch(line)) continue;

      final nums = RegExp(r'\d{4,5}')
          .allMatches(rawLine)
          .map((m) => m.group(0)!)
          .toList();
      if (nums.isEmpty) continue;

      if (nums.every((n) => n.length == 5)) {
        fiveDigitLines.add(rawLine);
      } else if (nums.every((n) => n.length == 4)) {
        fourDigitLines.add(rawLine);
      }
    }

    final secondNums = _numbersFromLines(fiveDigitLines, 5);
    final thirdNums = _numbersFromLines(
      fourDigitLines.length >= 2 ? fourDigitLines.sublist(0, 2) : fourDigitLines,
      4,
    );
    final fourthLines = fourDigitLines.length > 2
        ? fourDigitLines.sublist(2)
        : <String>[];
    final fourthNums = _numbersFromLines(fourthLines, 4);

    return _buildDearPdfResult(
      drawCode: drawCode,
      day: day,
      firstPrize: firstPrize,
      secondNums: secondNums,
      thirdNums: thirdNums,
      fourthNums: fourthNums,
      fifthRaw: fifthRaw,
      complimentsFromLongGrid: fromLongGrid,
    );
  }

  static FetchedResultData _buildDearPdfResult({
    required String drawCode,
    required DateTime day,
    required String firstPrize,
    required List<String> secondNums,
    required List<String> thirdNums,
    required List<String> fourthNums,
    required List<String> fifthRaw,
    bool complimentsFromLongGrid = true,
  }) {
    final prizes = _emptyPrizes();
    prizes[0] = firstPrize;
    if (secondNums.isNotEmpty) prizes[1] = _last3(secondNums.first);
    if (thirdNums.isNotEmpty) prizes[2] = _last3(thirdNums.first);
    if (fourthNums.isNotEmpty) prizes[3] = _last3(fourthNums.first);
    prizes[4] = _dearFifthPrizeDisplay(fourthNums, fifthRaw);

    final compliments = complimentsFromNumbers(
      fifthRaw,
      fromLongGrid: complimentsFromLongGrid,
    );

    return FetchedResultData(
      drawCode: drawCode.trim().toUpperCase(),
      date: DateTime(day.year, day.month, day.day),
      prizes: prizes,
      compliments: compliments,
    );
  }

  static String? _dearDotInTimeSlot(String drawCode) {
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

  static String _dearDotInDateDmy(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return '${d.day.toString().padLeft(2, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.year}';
  }

  /// Daily PDF from dearlottery.in (often live before Nagaland/API).
  static Future<FetchedResultData?> fetchDearLotteryDotInPdf(
    String drawCode,
    DateTime date,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final slot = _dearDotInTimeSlot(code);
    if (slot == null) return null;
    final day = DateTime(date.year, date.month, date.day);
    final uri = Uri.parse(
      'https://dearlottery.in/uploads/${day.year}/$slot-${_dearDotInDateDmy(day)}.pdf',
    );
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200 || res.bodyBytes.length < 4096) return null;
      final text = _extractPdfText(res.bodyBytes);
      if (text.trim().isEmpty) return null;
      return _parseDearPdfText(code, day, text);
    } catch (e) {
      debugPrint('DearFastResultSource.fetchDearLotteryDotInPdf $code: $e');
      return null;
    }
  }

  static List<String> _numbersFromLines(List<String> lines, int width) {
    final out = <String>[];
    final pattern = RegExp(width == 5 ? r'\d{5}' : r'\d{4}');
    for (final line in lines) {
      for (final m in pattern.allMatches(line)) {
        out.add(m.group(0)!);
      }
    }
    return out;
  }

  static List<String> _sortedCompliments(List<String> raw) {
    final numbers = <int>[];
    for (final item in raw) {
      if (!_isValidCell(item)) continue;
      final d = item.replaceAll(RegExp(r'[^0-9]'), '');
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

  static bool hasFullResult(FetchedResultData data) {
    if (!_isValidCell(data.prizes[0])) return false;
    if (!_isValidCell(data.prizes[1])) return false;
    return data.compliments.any(_isValidCell);
  }
}
