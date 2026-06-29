// ---------------------------------------------------------------------------
// Booking model
// ---------------------------------------------------------------------------

enum BookingCategory {
  oneDigitOrWord,
  threeDigit,
  twoLetterTwoDigit,
  tripleDot,
  permutation,
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

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Extracts customer name and bookings from WhatsApp message.
Map<String, dynamic> parseWhatsAppFull(String text) {
  final outcome = parseWhatsAppWithRemainder(text);
  return {'name': outcome.customerName, 'bookings': outcome.bookings};
}

/// Parse result with unparsed lines kept for paste preview re-edit.
class WhatsAppParseOutcome {
  const WhatsAppParseOutcome({
    required this.bookings,
    required this.remainingText,
    this.customerName,
  });

  final List<Booking> bookings;
  final String remainingText;
  final String? customerName;
}

List<Booking> parseWhatsAppMessage(String text) =>
    parseWhatsAppWithRemainder(text).bookings;

WhatsAppParseOutcome parseWhatsAppWithRemainder(String text) {
  try {
    final cleaned = _stripWhatsAppNoise(text);
    if (cleaned.isEmpty) {
      return WhatsAppParseOutcome(
        bookings: [],
        remainingText: text.trim(),
        customerName: extractCustomerName(text),
      );
    }

    final lines = cleaned
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return WhatsAppParseOutcome(
        bookings: [],
        remainingText: text.trim(),
        customerName: extractCustomerName(text),
      );
    }

    final results = <Booking>[];
    final consumed = <int>{};
    final handledLines = <int>{};
    int? pendingBoardHeaderIndex;

    _parseSuperBoxBlocks(lines, results, consumed);
    _parseTrailingCountBlocks(lines, results, consumed);
    _parseTwoDBoardBlocks(lines, results, consumed);

    String? pending1dBoard;
    List<String>? pending2dBoards;
    bool pending2dSticky = false;

    for (var i = 0; i < lines.length; i++) {
      if (consumed.contains(i)) continue;
      final line = lines[i];

      final boardOnly = _parseBoardOnlyLine(line);
      if (boardOnly != null) {
        pendingBoardHeaderIndex = i;
        if (boardOnly.is1d) {
          pending1dBoard = boardOnly.group1d;
          pending2dBoards = null;
          pending2dSticky = false;
        } else {
          pending2dBoards = boardOnly.boards2d;
          pending1dBoard = null;
          pending2dSticky = boardOnly.sticky2d;
        }
        continue;
      }

      final pendingApplied = _applyPendingBoardLine(
        line,
        pending1dBoard,
        pending2dBoards,
      );
      if (pendingApplied != null) {
        results.addAll(pendingApplied);
        handledLines.add(i);
        if (pendingBoardHeaderIndex != null) {
          handledLines.add(pendingBoardHeaderIndex);
          pendingBoardHeaderIndex = null;
        }
        if (pending1dBoard != null) {
          pending1dBoard = null;
        } else if (!pending2dSticky) {
          pending2dBoards = null;
        }
        continue;
      }

      if (pending2dSticky) {
        pending2dBoards = null;
        pending2dSticky = false;
        pendingBoardHeaderIndex = null;
      }

      final lineBookings = _parseSingleLine(line);
      if (lineBookings.isNotEmpty) {
        results.addAll(lineBookings);
        handledLines.add(i);
        if (pendingBoardHeaderIndex != null) {
          handledLines.add(pendingBoardHeaderIndex);
          pendingBoardHeaderIndex = null;
        }
        pending1dBoard = null;
        pending2dBoards = null;
        pending2dSticky = false;
      }
    }

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!consumed.contains(i) && !handledLines.contains(i)) {
        remaining.add(lines[i]);
      }
    }

    return WhatsAppParseOutcome(
      bookings: results,
      remainingText: remaining.join('\n'),
      customerName: extractCustomerName(text),
    );
  } catch (_) {
    return WhatsAppParseOutcome(
      bookings: [],
      remainingText: text.trim(),
      customerName: null,
    );
  }
}

String? extractCustomerName(String text) {
  for (var line in text.split('\n')) {
    final clean = line.trim();
    if (clean.isEmpty) continue;

    final headerName = RegExp(r'^\[[^\]]+\]\s*([^:]+):');
    final hm = headerName.firstMatch(clean);
    if (hm != null) {
      final name = hm.group(1)!.trim();
      if (name.isNotEmpty && !RegExp(r'^\d+$').hasMatch(name)) {
        return name;
      }
      continue;
    }

    if (clean.startsWith('[') && clean.contains(']')) continue;
    if (!RegExp(r'[0-9]').hasMatch(clean) && clean.length > 2) {
      return clean;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Multi-line blocks
// ---------------------------------------------------------------------------

void _parseSuperBoxBlocks(
  List<String> lines,
  List<Booking> out,
  Set<int> consumed,
) {
  if (lines.length < 2) return;

  for (var end = lines.length - 1; end >= 1; end--) {
    if (consumed.contains(end)) continue;
    final last = lines[end];
    final superBox = _parseSuperBoxCountLine(last, blockFooter: true);
    if (superBox == null) continue;

    final numbers = <String>[];
    for (var i = 0; i < end; i++) {
      if (consumed.contains(i)) continue;
      numbers.addAll(_extractThreeDigitTokens(lines[i]));
    }
    if (numbers.isEmpty) continue;

    for (var i = 0; i < end; i++) {
      if (!consumed.contains(i)) consumed.add(i);
    }
    consumed.add(end);

    for (final n in numbers) {
      if (superBox.superQty > 0) {
        out.add(
          Booking(
            category: BookingCategory.tripleDot,
            itemNumber: n,
            quantity: superBox.superQty,
            wordOrBoard: 'SUPER',
          ),
        );
      }
      if (superBox.boxQty > 0) {
        out.add(
          Booking(
            category: BookingCategory.tripleDot,
            itemNumber: n,
            quantity: superBox.boxQty,
            wordOrBoard: 'BOX',
          ),
        );
      }
    }
    break;
  }
}

void _parseTrailingCountBlocks(
  List<String> lines,
  List<Booking> out,
  Set<int> consumed,
) {
  if (lines.isEmpty) return;

  for (var end = lines.length - 1; end >= 0; end--) {
    if (consumed.contains(end)) continue;
    final last = lines[end];
    final count = _parseTrailingCountOnly(last);
    if (count == null) continue;

    final numbers = <String>[];
    var start = end;
    for (var i = end - 1; i >= 0; i--) {
      if (consumed.contains(i)) break;
      final line = lines[i];
      if (!_lineHasThreeDigitNumbers(line)) break;
      numbers.insertAll(0, _extractThreeDigitTokens(line));
      start = i;
    }
    if (numbers.isEmpty) continue;

    for (var i = start; i <= end; i++) {
      consumed.add(i);
    }
    for (final n in numbers) {
      out.add(
        Booking(
          category: BookingCategory.threeDigit,
          itemNumber: n,
          quantity: count,
        ),
      );
    }
    break;
  }
}

bool _lineIsThreeDigitOnly(String line) {
  final tokens = _splitTokens(line);
  if (tokens.isEmpty) return false;
  return tokens.every(
    (t) => t.length == 3 && RegExp(r'^\d{3}$').hasMatch(t),
  );
}

/// Line is a 3-digit numbers list (ignore junk like "..."), not number-count pairs.
bool _lineIsThreeDigitNumberList(String line) {
  final digits =
      _splitTokens(line).where((t) => RegExp(r'^\d+$').hasMatch(t)).toList();
  if (digits.length < 2) return false;
  return digits.every((t) => t.length == 3 && RegExp(r'^\d{3}$').hasMatch(t));
}

void _parseTwoDBoardBlocks(
  List<String> lines,
  List<Booking> out,
  Set<int> consumed,
) {
  for (var i = 0; i < lines.length - 1; i++) {
    if (consumed.contains(i)) continue;
    final boards = _parseTwoDBoardHeaderLine(lines[i]);
    if (boards == null || boards.isEmpty) continue;

    final twoDigits = <String>[];
    var j = i + 1;
    for (; j < lines.length; j++) {
      if (consumed.contains(j)) break;
      final line = lines[j];
      final tokens = _splitTokens(line);
      if (tokens.isEmpty) break;

      if (tokens.length == 1 && tokens[0].length == 1) {
        final count = int.tryParse(tokens[0]) ?? 0;
        if (count <= 0 || twoDigits.isEmpty) break;
        consumed.add(i);
        for (var k = i + 1; k <= j; k++) {
          consumed.add(k);
        }
        for (final board in boards) {
          for (final num in twoDigits) {
            out.add(
              Booking(
                category: BookingCategory.twoLetterTwoDigit,
                itemNumber: num,
                quantity: count,
                wordOrBoard: board,
              ),
            );
          }
        }
        break;
      }

      final nums = _extractTwoDigitTokens(line);
      if (nums.isEmpty) break;
      twoDigits.addAll(nums);
    }
  }
}

// ---------------------------------------------------------------------------
// Single-line parsing (priority order)
// ---------------------------------------------------------------------------

List<Booking> _parseSingleLine(String line) {
  // 1+1 / 1.1 super+box count line — never 1D booking.
  if (_parseSuperBoxCountLine(line) != null) return [];

  // Space-separated 3-digit list — count comes from a separate last line only.
  if (_lineIsThreeDigitNumberList(line)) return [];

  final setbox = _parseSetboxLine(line);
  if (setbox.isNotEmpty) return setbox;

  final box = _parseBoxLine(line);
  if (box.isNotEmpty) return box;

  final boards = _parseBoardFormatsLine(line);
  if (boards.isNotEmpty) return boards;

  final superHyphen = _parseSuperBoxHyphenLine(line);
  if (superHyphen.isNotEmpty) return superHyphen;

  final oneDBoardHyphen = _parseOneDBoardHyphenLine(line);
  if (oneDBoardHyphen.isNotEmpty) return oneDBoardHyphen;

  final brackets = _parseBracketLine(line);
  if (brackets.isNotEmpty) return brackets;

  final triple = _parseTripleDotLine(line);
  if (triple.isNotEmpty) return triple;

  final pairs = _parseNumberCountPairsLine(line);
  if (pairs.isNotEmpty) return pairs;

  final multiLast = _parseMultipleLastCountLine(line);
  if (multiLast.isNotEmpty) return multiLast;

  final setSat = _parseSetSatLine(line);
  if (setSat.isNotEmpty) return setSat;

  return _parseNormalLine(line);
}

List<Booking> _parseSetboxLine(String line) {
  final results = <Booking>[];
  final patterns = <RegExp>[
    RegExp(
      '(?<!\\d)(\\d{3})\\s*${_bookingSepBetween()}\\s*set\\s*box\\s*${_bookingSepBetween()}\\s*(\\d+)(?!\\d)',
      caseSensitive: false,
    ),
    RegExp(r'(?<!\d)(\d{3})\s*setbox\s*(\d+)(?!\d)', caseSensitive: false),
    RegExp(r'(?<!\d)(\d{3})setbox(\d+)(?!\d)', caseSensitive: false),
  ];
  final seen = <String>{};
  for (final re in patterns) {
    for (final m in re.allMatches(line)) {
      final num = m.group(1)!;
      final qty = int.tryParse(m.group(2)!) ?? 0;
      if (qty <= 0) continue;
      final key = '$num:$qty';
      if (seen.contains(key)) continue;
      seen.add(key);
      for (final p in _uniquePermutations(num)) {
        results.add(
          Booking(
            category: BookingCategory.permutation,
            itemNumber: p,
            quantity: qty,
            wordOrBoard: 'SUPER',
          ),
        );
      }
    }
  }
  return results;
}

List<Booking> _parseBoxLine(String line) {
  if (RegExp(r'set\s*box', caseSensitive: false).hasMatch(line)) {
    return [];
  }
  final results = <Booking>[];
  final re = RegExp(
    '(?<!\\d)(\\d{3})\\s*${_bookingSepBetween()}\\s*box\\s*${_bookingSepBetween()}\\s*(\\d+)(?!\\d)',
    caseSensitive: false,
  );
  for (final m in re.allMatches(line)) {
    final num = m.group(1)!;
    final qty = int.tryParse(m.group(2)!) ?? 0;
    if (qty <= 0) continue;
    results.add(
      Booking(
        category: BookingCategory.threeDigit,
        itemNumber: num,
        quantity: qty,
        wordOrBoard: 'BOX',
      ),
    );
  }
  return results;
}

List<Booking> _parseBoardFormatsLine(String line) {
  final results = <Booking>[];
  final upper = line.toUpperCase();

  // AB.45.5 / BC.56.3 / AC.57 3
  final twoLetterRe = RegExp(
    '(?<![A-Za-z])(AB|BC|AC)\\s*${_bookingSepBetween(required: true)}\\s*(\\d{2})\\s*${_bookingSepBetween(required: true)}\\s*(\\d+)',
    caseSensitive: false,
  );
  for (final m in twoLetterRe.allMatches(line)) {
    final board = m.group(1)!.toUpperCase();
    final num = m.group(2)!;
    final qty = int.tryParse(m.group(3)!) ?? 0;
    if (qty <= 0 || !_isValidTwoDigit(num)) continue;
    results.add(
      Booking(
        category: BookingCategory.twoLetterTwoDigit,
        itemNumber: num,
        quantity: qty,
        wordOrBoard: board,
      ),
    );
  }
  if (results.isNotEmpty) return results;

  // A.5.5 / B.4.10 / C.4.20
  final oneLetterRe = RegExp(
    '(?<![A-Za-z])(A|B|C)\\s*${_bookingSepBetween(required: true)}\\s*(\\d)\\s*${_bookingSepBetween(required: true)}\\s*(\\d+)',
    caseSensitive: false,
  );
  for (final m in oneLetterRe.allMatches(line)) {
    final board = m.group(1)!.toUpperCase();
    final num = m.group(2)!;
    final qty = int.tryParse(m.group(3)!) ?? 0;
    if (qty <= 0 || !_isValidOneDigit(num)) continue;
    results.add(
      Booking(
        category: BookingCategory.oneDigitOrWord,
        itemNumber: num,
        quantity: qty,
        wordOrBoard: board,
      ),
    );
  }
  if (results.isNotEmpty) return results;

  // ABC.4.5 / ALLBORD.5 10 / ALL BORD patterns with number-count
  final allBoardRe = RegExp(
    '(?:ABC|ALL\\s*BORD|ALLBORD)\\s*${_bookingSepBetween(required: true)}\\s*(\\d)\\s*${_bookingSepBetween(required: true)}\\s*(\\d+)',
    caseSensitive: false,
  );
  for (final m in allBoardRe.allMatches(upper)) {
    final num = m.group(1)!;
    final qty = int.tryParse(m.group(2)!) ?? 0;
    if (qty <= 0 || !_isValidOneDigit(num)) continue;
    for (final board in const ['A', 'B', 'C']) {
      results.add(
        Booking(
          category: BookingCategory.oneDigitOrWord,
          itemNumber: num,
          quantity: qty,
          wordOrBoard: board,
        ),
      );
    }
  }
  return results;
}

List<Booking> _parseSuperBoxHyphenLine(String line) {
  final results = <Booking>[];
  final re = RegExp(r'(?<!\d)(\d{3})\s*-\s*(\d{1,3})\s*-\s*(\d{1,3})(?!\d)');
  for (final m in re.allMatches(line)) {
    final num = m.group(1)!;
    if (!_isValidThreeDigit(num)) continue;
    final superQty = int.tryParse(m.group(2)!) ?? 0;
    final boxQty = int.tryParse(m.group(3)!) ?? 0;
    if (superQty > 0) {
      results.add(
        Booking(
          category: BookingCategory.tripleDot,
          itemNumber: num,
          quantity: superQty,
          wordOrBoard: 'SUPER',
        ),
      );
    }
    if (boxQty > 0) {
      results.add(
        Booking(
          category: BookingCategory.tripleDot,
          itemNumber: num,
          quantity: boxQty,
          wordOrBoard: 'BOX',
        ),
      );
    }
  }
  return results;
}

List<Booking> _parseOneDBoardHyphenLine(String line) {
  final results = <Booking>[];
  final re = RegExp(
    r'(?<![A-Za-z])([ABC])\s*-\s*(\d)\s*-\s*(\d+)(?!\d)',
    caseSensitive: false,
  );
  for (final m in re.allMatches(line)) {
    final board = m.group(1)!.toUpperCase();
    final num = m.group(2)!;
    final qty = int.tryParse(m.group(3)!) ?? 0;
    if (qty <= 0 || !_isValidOneDigit(num)) continue;
    results.add(
      Booking(
        category: BookingCategory.oneDigitOrWord,
        itemNumber: num,
        quantity: qty,
        wordOrBoard: board,
      ),
    );
  }
  return results;
}

List<Booking> _parseBracketLine(String line) {
  final results = <Booking>[];
  // Closing bracket optional: 345(5) or 345(5
  final re = RegExp(r'(\d{1,3})\s*\(\s*(\d+)\s*\)?');
  for (final m in re.allMatches(line)) {
    final raw = m.group(1)!;
    final qty = int.tryParse(m.group(2)!) ?? 0;
    if (qty <= 0) continue;
    if (raw.length == 3 && _isValidThreeDigit(raw)) {
      results.add(
        Booking(
          category: BookingCategory.threeDigit,
          itemNumber: raw,
          quantity: qty,
        ),
      );
    } else if (raw.length == 2 && _isValidTwoDigit(raw)) {
      results.add(
        Booking(
          category: BookingCategory.twoLetterTwoDigit,
          itemNumber: raw,
          quantity: qty,
        ),
      );
    } else if (raw.length == 1 && _isValidOneDigit(raw)) {
      results.add(
        Booking(
          category: BookingCategory.oneDigitOrWord,
          itemNumber: raw,
          quantity: qty,
        ),
      );
    }
  }
  return results;
}

List<Booking> _parseTripleDotLine(String line) {
  final results = <Booking>[];
  // Super/box counts are small (1–2 digits), not 3-digit numbers.
  final re = RegExp(
    '(?<!\\d)(\\d{3})\\s*${_bookingSepBetween(required: true)}+\\s*(\\d{1,2})\\s*(?:[.\\s,×x\\*_\\-/#*]+)\\s*(\\d{1,2})(?!\\d)',
  );
  for (final m in re.allMatches(line)) {
    final num = m.group(1)!;
    final superQty = int.tryParse(m.group(2)!) ?? 0;
    final boxQty = int.tryParse(m.group(3)!) ?? 0;
    if (superQty > 0) {
      results.add(
        Booking(
          category: BookingCategory.tripleDot,
          itemNumber: num,
          quantity: superQty,
          wordOrBoard: 'SUPER',
        ),
      );
    }
    if (boxQty > 0) {
      results.add(
        Booking(
          category: BookingCategory.tripleDot,
          itemNumber: num,
          quantity: boxQty,
          wordOrBoard: 'BOX',
        ),
      );
    }
  }
  return results;
}

List<Booking> _parseNumberCountPairsLine(String line) {
  if (RegExp(r'set\s*box|setbox|box|abc|allbord|all\s*bord', caseSensitive: false)
      .hasMatch(line)) {
    return [];
  }
  if (_lineIsThreeDigitNumberList(line)) return [];

  final tokens = _splitTokens(line);
  if (tokens.length < 4 || tokens.length % 2 != 0) return [];

  final allPairs = <Booking>[];
  for (var i = 0; i < tokens.length; i += 2) {
    final numTok = tokens[i];
    final countTok = tokens[i + 1];
    if (!RegExp(r'^\d+$').hasMatch(numTok) ||
        !RegExp(r'^\d+$').hasMatch(countTok)) {
      return [];
    }
    // Clear alternating pair: 3-digit number + short count (not another 3-digit).
    if (numTok.length == 3 && countTok.length == 3) return [];
    if (numTok.length == 3 && countTok.length > 2) return [];

    final qty = int.tryParse(countTok) ?? 0;
    if (qty <= 0) return [];

    final b = _normalBooking(numTok, qty);
    if (b == null) return [];
    allPairs.add(b);
  }
  return allPairs;
}

List<Booking> _parseMultipleLastCountLine(String line) {
  if (RegExp(r'set\s*box|setbox|box|abc|allbord|\(', caseSensitive: false)
      .hasMatch(line)) {
    return [];
  }
  if (_lineIsThreeDigitNumberList(line)) return [];

  final tokens = _splitTokens(line);
  if (tokens.length < 2) return [];

  final last = tokens.last;
  final count = int.tryParse(last) ?? 0;
  if (count <= 0) return [];

  final numTokens = tokens.sublist(0, tokens.length - 1);
  if (numTokens.isEmpty) return [];

  // All tokens are 3-digit → numbers list, not "numbers + last count".
  if (tokens.every((t) => t.length == 3 && RegExp(r'^\d{3}$').hasMatch(t))) {
    return [];
  }

  // Last token must be shorter than number tokens (count, not 3-digit number).
  final maxNumLen =
      numTokens.map((t) => t.length).fold<int>(0, (a, b) => a > b ? a : b);
  if (last.length >= maxNumLen && last.length == 3) return [];

  final results = <Booking>[];
  for (final tok in numTokens) {
    if (!RegExp(r'^\d+$').hasMatch(tok)) return [];
    if (tok.length == 3) {
      if (!_isValidThreeDigit(tok)) return [];
      results.add(
        Booking(
          category: BookingCategory.threeDigit,
          itemNumber: tok,
          quantity: count,
        ),
      );
    } else if (tok.length == 2) {
      if (!_isValidTwoDigit(tok)) return [];
      results.add(
        Booking(
          category: BookingCategory.twoLetterTwoDigit,
          itemNumber: tok,
          quantity: count,
        ),
      );
    } else if (tok.length == 1) {
      if (!_isValidOneDigit(tok)) return [];
      results.add(
        Booking(
          category: BookingCategory.oneDigitOrWord,
          itemNumber: tok,
          quantity: count,
        ),
      );
    } else {
      return [];
    }
  }
  return results.length >= 2 ? results : [];
}

List<Booking> _parseSetSatLine(String line) {
  final results = <Booking>[];
  final re = RegExp(
    '(?:SET|SAT)\\s*(\\d{3})\\s*${_bookingSepBetween(required: true)}\\s*(\\d+)',
    caseSensitive: false,
  );
  for (final m in re.allMatches(line)) {
    final num = m.group(1)!;
    final qty = int.tryParse(m.group(2)!) ?? 0;
    if (qty <= 0) continue;
    for (final p in _uniquePermutations(num)) {
      results.add(
        Booking(
          category: BookingCategory.permutation,
          itemNumber: p,
          quantity: qty,
          wordOrBoard: 'SUPER',
        ),
      );
    }
  }
  return results;
}

List<Booking> _parseNormalLine(String line) {
  if (_parseSuperBoxCountLine(line) != null) return [];
  if (_looksLikeBoardKeywordLine(line)) return [];
  if (_lineIsThreeDigitNumberList(line)) return [];

  final results = <Booking>[];
  final re = RegExp(
    '(?<!\\d)(\\d{1,3})\\s*${_bookingSepBetween(required: true)}\\s*(\\d+)(?!\\d)',
  );
  for (final m in re.allMatches(line)) {
    final num = m.group(1)!;
    final countStr = m.group(2)!;
    final qty = int.tryParse(countStr) ?? 0;
    if (qty <= 0) continue;

    // Never treat 3-digit + following digits as number-count on a number list line.
    if (num.length == 3 && countStr.length >= 2) {
      if (_extractThreeDigitTokens(line).length >= 2) continue;
      if (countStr.length == 3) continue;
    }

    final b = _normalBooking(num, qty);
    if (b != null) results.add(b);
  }
  return results;
}

Booking? _normalBooking(String num, int qty) {
  if (num.length == 3 && _isValidThreeDigit(num)) {
    return Booking(
      category: BookingCategory.threeDigit,
      itemNumber: num,
      quantity: qty,
    );
  }
  if (num.length == 2 && _isValidTwoDigit(num)) {
    return Booking(
      category: BookingCategory.twoLetterTwoDigit,
      itemNumber: num,
      quantity: qty,
    );
  }
  if (num.length == 1 && _isValidOneDigit(num)) {
    return Booking(
      category: BookingCategory.oneDigitOrWord,
      itemNumber: num,
      quantity: qty,
    );
  }
  return null;
}

// ---------------------------------------------------------------------------
// Pending board lines
// ---------------------------------------------------------------------------

class _BoardOnlyLine {
  _BoardOnlyLine({
    this.group1d,
    this.boards2d,
    this.sticky2d = false,
  });

  final String? group1d;
  final List<String>? boards2d;
  final bool sticky2d;
  bool get is1d => group1d != null;
}

_BoardOnlyLine? _parseBoardOnlyLine(String line) {
  if (RegExp(r'\d').hasMatch(line)) return null;
  final compact = line.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
  if (compact.isEmpty) return null;

  if (_isAllBordToken(compact)) {
    return _BoardOnlyLine(group1d: 'ABC');
  }
  if (compact == 'ABC') {
    return _BoardOnlyLine(group1d: 'ABC');
  }
  if (compact == 'A' || compact == 'B' || compact == 'C') {
    return _BoardOnlyLine(group1d: compact);
  }

  if (compact == 'AB' || compact == 'BC' || compact == 'AC') {
    return _BoardOnlyLine(boards2d: [compact], sticky2d: true);
  }

  final twoBoards = <String>[];
  for (final part in compact.split(RegExp(r'\s+'))) {
    final p = part.trim();
    if (p == 'AB' || p == 'BC' || p == 'AC') {
      twoBoards.add(p);
    }
  }
  if (twoBoards.isNotEmpty &&
      twoBoards.length == compact.split(RegExp(r'\s+')).length) {
    return _BoardOnlyLine(
      boards2d: twoBoards,
      sticky2d: twoBoards.length == 1,
    );
  }
  return null;
}

List<Booking>? _applyPendingBoardLine(
  String line,
  String? pending1d,
  List<String>? pending2dBoards,
) {
  if (pending1d == null && pending2dBoards == null) return null;

  final tokens = _splitTokens(line);
  if (tokens.length != 2) return null;
  final numTok = tokens[0];
  final countTok = tokens[1];
  if (!RegExp(r'^\d+$').hasMatch(numTok) ||
      !RegExp(r'^\d+$').hasMatch(countTok)) {
    return null;
  }
  final qty = int.tryParse(countTok) ?? 0;
  if (qty <= 0) return null;

  final results = <Booking>[];

  if (pending1d != null) {
    if (!_isValidOneDigit(numTok)) return null;
    final boards =
        pending1d == 'ABC' ? const ['A', 'B', 'C'] : [pending1d];
    for (final board in boards) {
      results.add(
        Booking(
          category: BookingCategory.oneDigitOrWord,
          itemNumber: numTok,
          quantity: qty,
          wordOrBoard: board,
        ),
      );
    }
    return results;
  }

  if (pending2dBoards != null) {
    if (!_isValidTwoDigit(numTok)) return null;
    for (final board in pending2dBoards) {
      results.add(
        Booking(
          category: BookingCategory.twoLetterTwoDigit,
          itemNumber: numTok,
          quantity: qty,
          wordOrBoard: board,
        ),
      );
    }
    return results;
  }

  return null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Separators: . space , - _ * × x / # = + (incl. multiples). Brackets used for counts.
const String _bookingSepClass = r'.\s,×x\*_\-/#=+';

String _bookingSepBetween({bool required = false}) =>
    required ? '(?:[$_bookingSepClass]+)' : '(?:[$_bookingSepClass]+)?';

String _stripWhatsAppNoise(String raw) {
  var t = raw.replaceAll(RegExp(r'[\uFEFF\u200B-\u200D\u2060]'), '');
  t = t.replaceAll(RegExp(r'\r\n?'), '\n');

  final headerWithContent = RegExp(r'^\[[^\]]+\]\s*[^:]*:\s*(.+)$');
  final headerOnly = RegExp(r'^\[[^\]]+\]\s*[^:]*:\s*$');

  final out = <String>[];
  for (final rawLine in t.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;

    final withContent = headerWithContent.firstMatch(line);
    if (withContent != null) {
      line = (withContent.group(1) ?? '').trim();
      if (line.isEmpty) continue;
    } else if (headerOnly.hasMatch(line)) {
      continue;
    }

    out.add(line);
  }

  return out.join('\n').trim();
}

List<String> _splitTokens(String line) {
  return line
      .replaceAll('×', 'x')
      .split(RegExp('[$_bookingSepClass]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

List<String> _extractThreeDigitTokens(String line) {
  return RegExp(r'\b(\d{3})\b')
      .allMatches(line)
      .map((m) => m.group(1)!)
      .where(_isValidThreeDigit)
      .toList();
}

List<String> _extractTwoDigitTokens(String line) {
  return RegExp(r'\b(\d{2})\b')
      .allMatches(line)
      .map((m) => m.group(1)!)
      .where(_isValidTwoDigit)
      .toList();
}

bool _lineHasThreeDigitNumbers(String line) {
  return _extractThreeDigitTokens(line).isNotEmpty;
}

int? _parseTrailingCountOnly(String line) {
  final tokens = _splitTokens(line);
  if (tokens.length != 1) return null;
  final count = int.tryParse(tokens[0]) ?? 0;
  return count > 0 ? count : null;
}

class _SuperBoxCount {
  _SuperBoxCount(this.superQty, this.boxQty);
  final int superQty;
  final int boxQty;
}

_SuperBoxCount? _parseSuperBoxCountLine(String line, {bool blockFooter = false}) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  // 1+1 / 1 + 1 / 1.1 — single-digit super + box counts (not 3.5 which is 1D).
  final plusDot = RegExp(r'^\s*(\d)\s*([.+])\s*(\d)\s*$');
  final m = plusDot.firstMatch(trimmed);
  if (m != null) {
    final a = int.tryParse(m.group(1)!) ?? 0;
    final b = int.tryParse(m.group(3)!) ?? 0;
    if (a > 0 && b > 0) {
      if (blockFooter || (a == 1 && b == 1)) {
        return _SuperBoxCount(a, b);
      }
    }
  }

  return null;
}

List<String>? _parseTwoDBoardHeaderLine(String line) {
  if (RegExp(r'\d').hasMatch(line)) return null;
  final boards = <String>[];
  for (final part in line.toUpperCase().split(RegExp(r'\s+'))) {
    final p = part.trim();
    if (p == 'AB' || p == 'BC' || p == 'AC') {
      boards.add(p);
    }
  }
  if (boards.isEmpty) return null;
  final parts = line.trim().split(RegExp(r'\s+'));
  if (boards.length != parts.length) return null;
  return boards;
}

bool _looksLikeBoardKeywordLine(String line) {
  final u = line.toUpperCase().trim();
  return u == 'ABC' ||
      u == 'ALLBORD' ||
      u == 'ALL BORD' ||
      _isAllBordToken(u);
}

bool _isAllBordToken(String token) {
  final t = token.replaceAll(RegExp(r'[^A-Z]'), '');
  if (t == 'ALLBORD' || t == 'ALLBORD') return true;
  if (t.contains('ALL') && t.contains('BORD')) return true;
  if (t.contains('ALL') && t.contains('NORD')) return true;
  return false;
}

bool _isValidOneDigit(String s) =>
    s.length == 1 && RegExp(r'^\d$').hasMatch(s);

bool _isValidTwoDigit(String s) =>
    s.length == 2 && RegExp(r'^\d{2}$').hasMatch(s);

bool _isValidThreeDigit(String s) =>
    s.length == 3 && RegExp(r'^\d{3}$').hasMatch(s);

List<String> _uniquePermutations(String s) {
  if (s.length != 3) return [s];
  final a = s[0], b = s[1], c = s[2];
  return <String>{
    '$a$b$c',
    '$a$c$b',
    '$b$a$c',
    '$b$c$a',
    '$c$a$b',
    '$c$b$a',
  }.toList();
}
