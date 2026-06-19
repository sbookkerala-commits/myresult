import 'dart:core';

enum BookingParseMode { digit1, digit2, digit3 }

class ParsedBooking {
  final BookingParseMode mode;
  final String itemNumber; // ഇത് String ആയി നിലനിർത്തുന്നു (039 എന്നത് 039 ആയി തന്നെ ഇരിക്കും)
  final String quantity;
  final String? boardLetters;

  const ParsedBooking({
    required this.mode,
    required this.itemNumber,
    required this.quantity,
    this.boardLetters,
  });
}

// -----------------------------------------------------------------------------
// 1. വാട്സാപ്പ് മെറ്റാഡാറ്റ ശുദ്ധീകരണം
// -----------------------------------------------------------------------------
String _cleanWhatsAppText(String raw) {
  var t = raw.replaceAll(RegExp(r'[\uFEFF\u200B-\u200D\u2060]'), '');

  // ബ്രാക്കറ്റിലെ തിയ്യതിയും സമയവും പൂർണ്ണമായും മാറ്റുന്നു: [18/04, 7:54 pm]
  t = t.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');

  // ബ്രാക്കറ്റ് ഇല്ലാത്ത തിയ്യതി ഫോർമാറ്റുകൾ (ഉദാ: 18/04/26, 7:54 pm - Name:)
  t = t.replaceAll(RegExp(r'\d{1,2}/\d{1,2}/\d{2,4}.*?:\s*'), ' ');

  return t;
}

// -----------------------------------------------------------------------------
// 2. പ്രധാന ഫംഗ്ഷൻ (1, 2, 3 ഡിജിറ്റുകൾ വേർതിരിക്കുന്നു)
// -----------------------------------------------------------------------------
List<ParsedBooking> parseAndCategorizeBookings(String text) {
  final cleanedText = _cleanWhatsAppText(text);
  final List<ParsedBooking> results = [];

  // വരികളായി തിരിക്കുന്നു
  final lines = cleanedText.split(RegExp(r'[\n\r,;|]+'));

  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;

    // --- MODE 3: 3-Digit (039/10, 591.5, 089 15) ---
    // നിയമം: കൃത്യം 3 അക്കങ്ങൾ + ചിഹ്നം + എണ്ണം
    final re3 = RegExp(r'(?<!\d)(\d{3})(?!\d)[^\d\s]*\s*(\d+)');
    for (final m in re3.allMatches(line)) {
      results.add(ParsedBooking(
        mode: BookingParseMode.digit3,
        itemNumber: m.group(1)!, // ഇവിടെയാണ് പൂജ്യം നിലനിൽക്കുന്നത്
        quantity: m.group(2)!,
      ));
      line = line.replaceFirst(m.group(0)!, " "); 
    }

    // --- MODE 2: 2-Digit Letters (Ab.35.3) ---
    final re2Let = RegExp(r'\b([A-Za-z]{2})[^\d]*(\d{2})[^\d]+(\d+)');
    for (final m in re2Let.allMatches(line)) {
      results.add(ParsedBooking(
        mode: BookingParseMode.digit2,
        boardLetters: m.group(1)!.toUpperCase(),
        itemNumber: m.group(2)!,
        quantity: m.group(3)!,
      ));
      line = line.replaceFirst(m.group(0)!, " ");
    }

    // --- MODE 2: 2-Digit Plain (39.30) ---
    // കലണ്ടർ തിയ്യതികൾ ഒഴിവാക്കാൻ (18/04 പോലെ 31-ൽ താഴെ വരുന്നവ ബുക്കിംഗ് അല്ലെന്നു ഉറപ്പുവരുത്തുക)
    final re2Num = RegExp(r'(?<!\d)(\d{2})(?!\d)[^\d\s]*\s*(\d+)');
    for (final m in re2Num.allMatches(line)) {
      results.add(ParsedBooking(
        mode: BookingParseMode.digit2,
        itemNumber: m.group(1)!,
        quantity: m.group(2)!,
      ));
      line = line.replaceFirst(m.group(0)!, " ");
    }

    // --- MODE 1: 1-Digit (A. 5.5) ---
    final re1 = RegExp(r'\b([A-Za-z]{1,3})[^\d]*(\d{1})[^\d]+(\d+)');
    for (final m in re1.allMatches(line)) {
      results.add(ParsedBooking(
        mode: BookingParseMode.digit1,
        boardLetters: m.group(1)!.toUpperCase(),
        itemNumber: m.group(2)!,
        quantity: m.group(3)!,
      ));
    }
  }

  // ആവർത്തനം ഒഴിവാക്കുന്നു
  final seen = <String>{};
  return results.where((b) => seen.add("${b.mode}${b.itemNumber}${b.quantity}${b.boardLetters}")).toList();
}