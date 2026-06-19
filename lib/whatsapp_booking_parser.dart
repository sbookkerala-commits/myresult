// ---------------------------------------------------------------------------
// Booking model
// ---------------------------------------------------------------------------

enum BookingCategory {
  oneDigitOrWord,
  threeDigit,
  twoLetterTwoDigit,
  tripleDot, // New: for 997...4*3
  permutation, // New: for SET/SAT
}

class Booking {
  const Booking({
    required this.category,
    required this.itemNumber,
    required this.quantity,
    this.wordOrBoard,
  });

  final BookingCategory category;
  final String itemNumber;
  final int quantity;
  final String? wordOrBoard;

  @override
  String toString() =>
      'Booking($category, item=$itemNumber, qty=$quantity, word=${wordOrBoard ?? "-"})';
}

class _SpanMatch {
  _SpanMatch({
    required this.start,
    required this.end,
    required this.booking,
    required this.priority,
  });

  final int start;
  final int end;
  final Booking booking;
  final int priority;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Extracts customer name and bookings from WhatsApp message.
Map<String, dynamic> parseWhatsAppFull(String text) {
  final name = extractCustomerName(text);
  final bookings = parseWhatsAppMessage(text);
  return {'name': name, 'bookings': bookings};
}

String? extractCustomerName(String text) {
  final lines = text.split('\n');
  for (var line in lines) {
    final clean = line.trim();
    if (clean.isEmpty) continue;
    // Skip WhatsApp metadata lines [12:30 PM, 1/1/2026] Name:
    if (clean.startsWith('[') && clean.contains(']')) continue;
    // If line doesn't have numbers, it's likely a name
    if (!RegExp(r'[0-9]').hasMatch(clean) && clean.length > 2) {
      return clean;
    }
  }
  return null;
}

List<Booking> parseWhatsAppMessage(String text) {
  final cleaned = _stripWhatsAppNoise(text);
  if (cleaned.isEmpty) return [];

  final candidates = <_SpanMatch>[];

  // 1. SET/SAT Permutation (Priority 7)
  final setRegex =
      RegExp(r'(SET|SAT)\s*(\d{3})\s*[\*\-x\s]\s*(\d+)', caseSensitive: false);
  for (final m in setRegex.allMatches(cleaned)) {
    final numStr = m.group(2)!;
    final qtyStr = m.group(3)!;
    final qty = int.tryParse(qtyStr) ?? 0;
    final perms = _generatePermutations(numStr);
    for (final p in perms) {
      candidates.add(_SpanMatch(
        start: m.start,
        end: m.end,
        booking: Booking(
            category: BookingCategory.permutation,
            itemNumber: p,
            quantity: qty,
            wordOrBoard: 'SUPER'),
        priority: 7,
      ));
    }
  }

  // 2. A list of numbers followed by one common quantity.
  // Examples: 111.222.333.444.10 and vertical WhatsApp lists ending in 10.
  final listRegex = RegExp(
    r'(?<!\d)((?:\d{3}\s*(?:[.\n]\s*)){2,}\d{3})\s*(?:[.\-*x/]\s*|\n\s*)(\d+)(?!\d)',
  );
  for (final m in listRegex.allMatches(cleaned)) {
    final qty = int.tryParse(m.group(2)!) ?? 0;
    for (final number in RegExp(r'\d{3}')
        .allMatches(m.group(1)!)
        .map((match) => match.group(0)!)) {
      candidates.add(_SpanMatch(
        start: m.start,
        end: m.end,
        booking: Booking(
            category: BookingCategory.threeDigit,
            itemNumber: number,
            quantity: qty),
        priority: 6,
      ));
    }
  }

  // 3. Board labels may be sent once before several following numbers.
  // Example: BC on one line, followed by 11.10 and 22.10.
  String? pendingBoard;
  var lineStart = 0;
  final pendingBoardRegex =
      RegExp(r'^(A|B|C|AB|BC|AC|ABC)$', caseSensitive: false);
  final labelledPairRegex =
      RegExp(r'(?<!\d)(\d{1,3})\s*[.\-*x/]\s*(\d+)(?!\d)');
  for (final line in cleaned.split('\n')) {
    final trimmed = line.trim();
    final boardMatch = pendingBoardRegex.firstMatch(trimmed);
    if (boardMatch != null) {
      pendingBoard = boardMatch.group(1)!.toUpperCase();
    } else if (pendingBoard != null) {
      for (final m in labelledPairRegex.allMatches(line)) {
        final boards =
            pendingBoard == 'ABC' ? const ['A', 'B', 'C'] : [pendingBoard];
        for (final board in boards) {
          candidates.add(_SpanMatch(
            start: lineStart + m.start,
            end: lineStart + m.end,
            booking: Booking(
              category: m.group(1)!.length == 2
                  ? BookingCategory.twoLetterTwoDigit
                  : (m.group(1)!.length == 3
                      ? BookingCategory.threeDigit
                      : BookingCategory.oneDigitOrWord),
              itemNumber: m.group(1)!,
              quantity: int.tryParse(m.group(2)!) ?? 0,
              wordOrBoard: board,
            ),
            priority: 6,
          ));
        }
      }
    }
    lineStart += line.length + 1;
  }

  // 4. SUPER/BOX split: 997...4*3 or 374.2.2.
  final tripleRegex = RegExp(r'(\d{3})\s*\.{1,}\s*(\d+)\s*[.*x\-]\s*(\d+)');
  for (final m in tripleRegex.allMatches(cleaned)) {
    final numStr = m.group(1)!;
    final superQty = int.tryParse(m.group(2)!) ?? 0;
    final boxQty = int.tryParse(m.group(3)!) ?? 0;
    if (superQty > 0) {
      candidates.add(_SpanMatch(
        start: m.start,
        end: m.end,
        booking: Booking(
            category: BookingCategory.tripleDot,
            itemNumber: numStr,
            quantity: superQty,
            wordOrBoard: 'SUPER'),
        priority: 5,
      ));
    }
    if (boxQty > 0) {
      candidates.add(_SpanMatch(
        start: m.start,
        end: m.end,
        booking: Booking(
            category: BookingCategory.tripleDot,
            itemNumber: numStr,
            quantity: boxQty,
            wordOrBoard: 'BOX'),
        priority: 5,
      ));
    }
  }

  // 5. Brackets Multiple Support (Priority 3): 018(10)423(10)
  final bracketRegex = RegExp(r'(\d{1,3})\s*\(\s*(\d+)\s*\)');
  for (final m in bracketRegex.allMatches(cleaned)) {
    candidates.add(_SpanMatch(
      start: m.start,
      end: m.end,
      booking: Booking(
        category: m.group(1)!.length == 3
            ? BookingCategory.threeDigit
            : BookingCategory.oneDigitOrWord,
        itemNumber: m.group(1)!,
        quantity: int.tryParse(m.group(2)!) ?? 0,
      ),
      priority: 3,
    ));
  }

  // 6. Two Letter + 2-digit (Priority 2)
  for (final m in _reTwoLetterTwoDigit.allMatches(cleaned)) {
    candidates.add(_SpanMatch(
      start: m.start,
      end: m.end,
      booking: Booking(
          category: BookingCategory.twoLetterTwoDigit,
          itemNumber: m.group(2)!,
          quantity: int.tryParse(m.group(3)!) ?? 0,
          wordOrBoard: m.group(1)!),
      priority: 2,
    ));
  }

  // 7. General Word + Num + Qty (Priority 1)
  for (final m in _reWordNumberQty.allMatches(cleaned)) {
    final word = m.group(1)!.toUpperCase();
    final boards = word == 'ABC' ? const ['A', 'B', 'C'] : [word];
    for (final board in boards) {
      candidates.add(_SpanMatch(
        start: m.start,
        end: m.end,
        booking: Booking(
            category: BookingCategory.oneDigitOrWord,
            itemNumber: m.group(2)!,
            quantity: int.tryParse(m.group(3)!) ?? 0,
            wordOrBoard: board),
        priority: 1,
      ));
    }
  }

  // 8. Simple Number + Qty: 123*10, 123-10, 591.5 or 786/10.
  final simpleRegex = RegExp(r'(?<!\d)(\d{1,3})\s*[\*.\-/x]\s*(\d+)(?!\d)');
  for (final m in simpleRegex.allMatches(cleaned)) {
    candidates.add(_SpanMatch(
      start: m.start,
      end: m.end,
      booking: Booking(
        category: m.group(1)!.length == 3
            ? BookingCategory.threeDigit
            : BookingCategory.oneDigitOrWord,
        itemNumber: m.group(1)!,
        quantity: int.tryParse(m.group(2)!) ?? 0,
      ),
      priority: 0,
    ));
  }

  return _mergeNonOverlapping(candidates).map((s) => s.booking).toList();
}

// Helpers
List<String> _generatePermutations(String s) {
  if (s.length <= 1) return [s];
  final result = <String>{};
  for (var i = 0; i < s.length; i++) {
    final char = s[i];
    final remaining = s.substring(0, i) + s.substring(i + 1);
    for (final p in _generatePermutations(remaining)) {
      result.add(char + p);
    }
  }
  return result.toList();
}

final RegExp _reTwoLetterTwoDigit = RegExp(
    r'(?<![A-Za-z])([A-Za-z]{2})(?![A-Za-z])[^\d]{0,10}?(\d{2})[^\d]{0,10}?(\d+)');
final RegExp _reWordNumberQty = RegExp(
    r'(?<![A-Za-z0-9])([A-Za-z]+)[^\d]{0,10}?(\d{1,3})[^\d]{0,10}?(\d+)');

String _stripWhatsAppNoise(String raw) {
  var t = raw.replaceAll(RegExp(r'[\uFEFF\u200B-\u200D\u2060]'), '');
  // Filter out [12:30 PM, 1/1/2026] style headers
  t = t.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  // Avoid stripping slashes that look like booking counts (e.g. 786/10)
  // but strip date headers like 1/1/2026 if they are inside metadata.

  t = t.replaceAll(RegExp(r'[ \t\f\v]+'), ' ');
  t = t.replaceAll(RegExp(r'\r\n?'), '\n');
  t = t.replaceAll('×', '*');
  return t.trim();
}

bool _overlaps(_SpanMatch a, _SpanMatch b) =>
    !(a.end <= b.start || a.start >= b.end);

List<_SpanMatch> _mergeNonOverlapping(List<_SpanMatch> input) {
  if (input.isEmpty) return [];
  input.sort((a, b) {
    final p = b.priority.compareTo(a.priority);
    if (p != 0) return p;
    return a.start.compareTo(b.start);
  });
  final taken = <_SpanMatch>[];
  for (final c in input) {
    if (!taken.any((t) =>
        _overlaps(t, c) &&
        !(t.start == c.start && t.end == c.end && t.priority == c.priority))) {
      taken.add(c);
    }
  }
  taken.sort((a, b) => a.start.compareTo(b.start));
  return taken;
}
