import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'dear_fast_result_source.dart';
import 'fetched_result_data.dart';
import 'ist_clock.dart';

/// Dear results via [dear-lottery.in] — publication gate + official PDF numbers.
///
/// dear-lottery.in publishes result charts as JPEGs. We use their WordPress API
/// to confirm the draw date and that today's/yesterday's chart is live, then read
/// the matching official Nagaland gazette PDF (same board as the uploaded image).
class DearLotteryInSource {
  static const _base = 'https://dear-lottery.in';
  static const _wpPages = '$_base/wp-json/wp/v2/pages';
  static const _nagalandPdfBase = 'https://nagalandlotteries.com/old_results';

  static const _todaySlugs = {
    'DEAR1': 'dear-lottery-result-today-1-pm',
    'DEAR6': 'dear-lottery-result-today-6-pm',
    'DEAR8': 'dear-lottery-result-today-8-pm',
  };

  static const _yesterdaySlug = 'dear-lottery-result-yesterday-8-pm-6-pm-1-pm';

  static String _drawLabel(String drawCode) {
    switch (drawCode.trim().toUpperCase()) {
      case 'DEAR1':
        return '1 PM';
      case 'DEAR6':
        return '6 PM';
      case 'DEAR8':
        return '8 PM';
      default:
        throw ArgumentError('Not a DEAR draw: $drawCode');
    }
  }

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

  static String _pdfFileName(DateTime day, String fileCode) {
    final d = DateTime(day.year, day.month, day.day);
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$fileCode$dd$mm$yy.PDF';
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Parses dates from dear-lottery.in page titles.
  @visibleForTesting
  static DateTime? parsePageDate(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();

    final long = RegExp(
      r'(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (long != null) {
      final day = int.tryParse(long.group(1)!);
      final month = _monthNumber(long.group(2)!);
      final year = int.tryParse(long.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    final short = RegExp(r'\((\d{1,2})-(\d{1,2})-(\d{4})\)').firstMatch(cleaned);
    if (short != null) {
      final day = int.tryParse(short.group(1)!);
      final month = int.tryParse(short.group(2)!);
      final year = int.tryParse(short.group(3)!);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  static int? _monthNumber(String name) {
    const months = {
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
    };
    return months[name.toLowerCase()];
  }

  /// First result chart image after a draw heading (e.g. "Today 1 PM").
  @visibleForTesting
  static String? extractResultImageUrl(
    String html, {
    required String drawLabel,
  }) {
    final normalized = html.replaceAll('\r', '');
    final headingPattern = RegExp(
      '<h2[^>]*>[^<]*${RegExp.escape(drawLabel)}[^<]*</h2>',
      caseSensitive: false,
      dotAll: true,
    );
    final heading = headingPattern.firstMatch(normalized);
    if (heading == null) return null;

    final after = normalized.substring(heading.end);
    final img = RegExp(
      r'<img[^>]+src="([^"]+\.(?:jpg|jpeg|png|webp))"',
      caseSensitive: false,
    ).firstMatch(after);
    return img?.group(1)?.replaceAll(r'\/', '/');
  }

  static Future<Map<String, dynamic>?> _fetchPageBySlug(String slug) async {
    try {
      final uri = Uri.parse('$_wpPages?slug=$slug');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! List || json.isEmpty) return null;
      final first = json.first;
      if (first is! Map) return null;
      return Map<String, dynamic>.from(first);
    } catch (e) {
      debugPrint('DearLotteryInSource._fetchPageBySlug($slug): $e');
      return null;
    }
  }

  static Future<String?> _pageHtmlForDay(
    String drawCode,
    DateTime day,
    DateTime now,
  ) async {
    final code = drawCode.trim().toUpperCase();
    final target = DateTime(day.year, day.month, day.day);
    final today = IstClock.calendarDay(at: now);
    final yesterday = today.subtract(const Duration(days: 1));

    if (_sameCalendarDay(target, today)) {
      final slug = _todaySlugs[code];
      if (slug == null) return null;
      final page = await _fetchPageBySlug(slug);
      if (page == null) return null;
      final title = page['title']?['rendered']?.toString() ?? '';
      final pageDay = parsePageDate(title);
      final html = page['content']?['rendered']?.toString();
      if (pageDay == null || !_sameCalendarDay(pageDay, target)) {
        final imageUrl = html == null
            ? null
            : extractResultImageUrl(html, drawLabel: _drawLabel(code));
        if (imageUrl == null || !imageUrl.contains('dear-lottery.in')) {
          debugPrint(
            'DearLotteryInSource: today page date mismatch for $code '
            '(expected $target, title="$title")',
          );
          return null;
        }
        debugPrint(
          'DearLotteryInSource: using chart for $code despite title date $pageDay',
        );
        return html;
      }
      return html;
    }

    if (_sameCalendarDay(target, yesterday)) {
      final page = await _fetchPageBySlug(_yesterdaySlug);
      return page?['content']?['rendered']?.toString();
    }

    return null;
  }

  static Future<bool> hasPublishedChart(
    String drawCode,
    DateTime day, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final html = await _pageHtmlForDay(drawCode, day, at);
    if (html == null || html.isEmpty) return false;
    final imageUrl = extractResultImageUrl(
      html,
      drawLabel: _drawLabel(drawCode),
    );
    return imageUrl != null && imageUrl.contains('dear-lottery.in');
  }

  static Future<String?> _fetchNagalandPdfText(
    String drawCode,
    DateTime day,
  ) async {
    final fileCode = _pdfFileCode(drawCode);
    if (fileCode == null) return null;
    final target = DateTime(day.year, day.month, day.day);
    for (final offset in const [0, -1, 1]) {
      final tryDay = target.add(Duration(days: offset));
      final fileName = _pdfFileName(tryDay, fileCode);
      final uri = Uri.parse('$_nagalandPdfBase/$fileName');
      try {
        final res = await http.get(uri).timeout(const Duration(seconds: 25));
        if (res.statusCode != 200 || res.bodyBytes.length < 1024) continue;
        if (!_looksLikePdf(res.bodyBytes)) continue;
        PdfDocument? document;
        try {
          document = PdfDocument(inputBytes: res.bodyBytes);
          final text = PdfTextExtractor(document).extractText();
          final parsed = DearFastResultSource.parseOfficialPdfText(
            drawCode,
            target,
            text,
          );
          if (parsed != null) {
            debugPrint(
              'DearLotteryInSource: PDF $fileName matched day $target',
            );
            return text;
          }
        } finally {
          document?.dispose();
        }
      } catch (e) {
        debugPrint('DearLotteryInSource._fetchNagalandPdfText $fileName: $e');
      }
    }
    return null;
  }

  static bool _looksLikePdf(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46;
  }

  /// Full Dear result when dear-lottery.in chart is live for [day].
  static Future<FetchedResultData?> fetch(
    String drawCode,
    DateTime date, {
    DateTime? now,
    bool requirePublishedChart = true,
  }) async {
    final code = drawCode.trim().toUpperCase();
    final day = DateTime(date.year, date.month, date.day);
    final at = now ?? DateTime.now();

    if (requirePublishedChart) {
      final published = await hasPublishedChart(code, day, now: at);
      if (!published) return null;
    }

    final text = await _fetchNagalandPdfText(code, day);
    if (text == null || text.trim().isEmpty) return null;
    return DearFastResultSource.parseOfficialPdfText(code, day, text);
  }
}
