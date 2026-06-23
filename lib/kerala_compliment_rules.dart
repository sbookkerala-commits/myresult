/// LOCKED — do not change without explicit user approval.
/// lockVersion: 2026-06-04
class KeralaComplimentRules {
  KeralaComplimentRules._();

  static const String lockVersion = '2026-06-04';

  static const int complimentCount = 30;
  static const int displayColumnCount = 3;
  static const int displayRowCount = 10;
  static const int ninthPrizeGridColumns = 5;
  static const int firstVerticalColumnPick = 29;

  static const Set<String> _noiseFourDigit = {'2000', '5000', '10000', '8377'};

  static final RegExp _declaredCountPattern = RegExp(
    r'(?:drawn|to be drawn)\s+(\d+)\s+times',
    caseSensitive: false,
  );

  static String normalizeCompliment3(String raw) {
    final d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '---';
    if (d.length <= 3) return d.padLeft(3, '0');
    return d.substring(d.length - 3);
  }

  static bool isValidComplimentCell(String v) {
    final t = v.trim();
    return t.isNotEmpty && t != '---';
  }

  static int? parseDeclaredNinthCount(String text) {
    final match = _declaredCountPattern.firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static bool ninthIsComplete(List<String> flatFourDigit, int? declared) {
    if (declared == null || declared <= 0) return false;
    return flatFourDigit.length >= declared;
  }

  static List<String> filterNinthGridNumbers(Iterable<String> raw) {
    final out = <String>[];
    for (final item in raw) {
      final t = item.trim();
      if (!RegExp(r'^\d{4}$').hasMatch(t)) continue;
      if (_noiseFourDigit.contains(t)) continue;
      out.add(t);
    }
    return out;
  }

  static List<List<String>> reshapeVerticalColumns(List<String> flat) {
    final cols = List.generate(
      ninthPrizeGridColumns,
      (_) => <String>[],
    );
    for (var i = 0; i < flat.length; i++) {
      cols[i % ninthPrizeGridColumns].add(flat[i]);
    }
    return cols;
  }

  static int _firstDigit(String four) {
    return int.tryParse(four.substring(0, 1)) ?? 0;
  }

  static void _sortColumnByFirstDigit(List<String> column) {
    column.sort((a, b) {
      final fa = _firstDigit(a);
      final fb = _firstDigit(b);
      if (fa != fb) return fa.compareTo(fb);
      return a.compareTo(b);
    });
  }

  static List<String> extractFromFlatNineGrid(List<String> flatFourDigit) {
    final cols = reshapeVerticalColumns(flatFourDigit);
    for (final col in cols) {
      _sortColumnByFirstDigit(col);
    }

    final picked = <String>[];
    void takeFromColumn(int colIndex, int max) {
      if (colIndex < 0 || colIndex >= cols.length) return;
      for (final four in cols[colIndex]) {
        if (picked.length >= complimentCount) return;
        if (max <= 0) return;
        picked.add(normalizeCompliment3(four));
        max--;
      }
    }

    takeFromColumn(0, firstVerticalColumnPick);
    for (var c = 1; c < cols.length && picked.length < complimentCount; c++) {
      takeFromColumn(c, complimentCount - picked.length);
    }

    final numbers = picked
        .where(isValidComplimentCell)
        .map((s) => int.tryParse(s) ?? -1)
        .where((n) => n >= 0)
        .toList()
      ..sort();
    final out = List<String>.filled(complimentCount, '---');
    for (var i = 0; i < numbers.length && i < complimentCount; i++) {
      out[i] = numbers[i].toString().padLeft(3, '0');
    }
    return out;
  }

  static List<String> ascendingSlots(Iterable<String> raw) {
    final numbers = <int>[];
    for (final item in raw) {
      if (!isValidComplimentCell(item)) continue;
      final n = int.tryParse(normalizeCompliment3(item));
      if (n == null) continue;
      numbers.add(n);
    }
    numbers.sort();
    final out = List<String>.filled(complimentCount, '---');
    for (var i = 0; i < numbers.length && i < complimentCount; i++) {
      out[i] = numbers[i].toString().padLeft(3, '0');
    }
    return out;
  }

  static List<String> forDisplay(Iterable<String> raw) => ascendingSlots(raw);

  static String displayValueAt(List<String> flat, int row, int column) {
    final index = column * displayRowCount + row;
    if (index < 0 || index >= flat.length) return '---';
    return flat[index];
  }

  static bool complimentsLookValid(Iterable<String> raw) {
    final slots = ascendingSlots(raw);
    var valid = 0;
    for (final c in slots) {
      if (isValidComplimentCell(c)) valid++;
    }
    if (valid < complimentCount) return false;
    return !slots.contains('877');
  }
}
