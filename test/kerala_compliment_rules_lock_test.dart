import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/kerala_compliment_rules.dart';
import 'package:sbook_lottery/services/kerala_result_fetcher.dart';

void main() {
  test('lockVersion unchanged', () {
    expect(KeralaComplimentRules.lockVersion, '2026-06-04');
  });

  test('SK55 fixture → 30 ascending compliments without 877', () async {
    final html = await File('tools/sk55_keralalotteries_net.html').readAsString();
    final day = DateTime(2026, 6, 5);
    final parsed = KeralaResultFetcher.parseHtml(html, day);
    expect(parsed, isNotNull);
    expect(parsed!.declaredNinthCount, 144);
    expect(parsed.ninthScrapedCount, greaterThanOrEqualTo(144));
    expect(parsed.ninthComplete, isTrue);
    expect(parsed.complimentsValid, isTrue);
    expect(
      KeralaComplimentRules.complimentsLookValid(parsed.compliments),
      isTrue,
    );
    expect(parsed.compliments.where((c) => c != '---').length, 30);
    expect(parsed.compliments, contains('006'));
    expect(parsed.compliments, isNot(contains('877')));

    final nums = parsed.compliments
        .where(KeralaComplimentRules.isValidComplimentCell)
        .map((s) => int.parse(s))
        .toList();
    expect(nums, orderedEquals(List<int>.from(nums)..sort()));

    // Golden first/last from locked rules (SK-55 / 05-06-2026).
    expect(parsed.compliments.first, '000');
    expect(parsed.compliments[1], '006');
    expect(parsed.compliments.last, '992');
  });

  test('displayValueAt uses column-down index', () {
    final flat = List<String>.generate(30, (i) => (i + 1).toString().padLeft(3, '0'));
    expect(KeralaComplimentRules.displayValueAt(flat, 0, 0), '001');
    expect(KeralaComplimentRules.displayValueAt(flat, 9, 0), '010');
    expect(KeralaComplimentRules.displayValueAt(flat, 0, 1), '011');
    expect(KeralaComplimentRules.displayValueAt(flat, 0, 2), '021');
  });
}
