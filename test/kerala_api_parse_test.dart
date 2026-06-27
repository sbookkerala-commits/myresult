import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/services/result_fetch_service.dart';

void main() {
  test('parses draw_date field from kerala api', () {
    final day = DateTime(2026, 6, 26);
    final data = ResultFetchService.parseKeralaApiJson(day, {
      'draw_date': '2026-06-26',
      'first': {'ticket': 'RW 628248'},
      'prizes': {
        '2nd': ['RW 583000'],
        '3rd': ['RW 659000'],
        '4th': ['0268'],
        '5th': ['0183'],
        '9th': List<String>.generate(144, (i) => (1000 + i).toString()),
      },
    });
    expect(data, isNotNull);
    expect(data!.prizes[0], '248');
    expect(data.compliments.where((c) => c != '---').length, 30);
  });

  test('rejects when draw_date mismatches', () {
    final data = ResultFetchService.parseKeralaApiJson(
      DateTime(2026, 6, 25),
      {'draw_date': '2026-06-26', 'first': {'ticket': 'RW 628248'}, 'prizes': {}},
    );
    expect(data, isNull);
  });
}
