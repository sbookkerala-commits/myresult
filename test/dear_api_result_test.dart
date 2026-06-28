import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/services/dear_fast_result_source.dart';
import 'package:sbook_lottery/services/result_fetch_service.dart';

void main() {
  const sampleJune26 = {
    'date': '2026-06-26',
    'time': '1pm',
    'prizes': {
      '1st': ['42C', '20001'],
      '2nd': ['03770', '04821'],
      '3rd': ['0371'],
      '4th': ['1034', '1368'],
      'cons': ['20001'],
      '5th': [
        '0041',
        '0309',
        '0527',
        '0658',
        '0773',
        '0791',
        '1051',
        '1054',
        '1414',
        '1589',
        '1759',
        '1764',
        '1856',
        '2005',
        '2198',
        '2450',
        '2650',
        '2670',
        '2710',
        '2756',
        '2821',
        '3108',
        '3135',
        '3294',
        '3377',
        '3425',
        '3455',
        '3535',
        '3571',
        '3577',
        '3810',
        '9999',
      ],
    },
  };

  test('parses dear api json using first 30 of 5th prize list', () {
    final day = DateTime(2026, 6, 26);
    final data = ResultFetchService.parseDearApiJson('DEAR1', day, sampleJune26);
    expect(data, isNotNull);
    expect(data!.prizes, ['001', '770', '371', '034', '368']);
    expect(data.compliments.first, '005');
    expect(data.compliments, isNot(contains('999')));
    expect(DearFastResultSource.hasFullResult(data), isTrue);
  });

  test('rejects api json when date mismatches', () {
    final day = DateTime(2026, 6, 25);
    final data = ResultFetchService.parseDearApiJson('DEAR1', day, sampleJune26);
    expect(data, isNull);
  });

  test('rejects api json when time slot mismatches', () {
    final day = DateTime(2026, 6, 26);
    final data = ResultFetchService.parseDearApiJson('DEAR6', day, sampleJune26);
    expect(data, isNull);
  });
}
