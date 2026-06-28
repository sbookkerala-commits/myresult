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
      '5th': [
        '0041',
        '0140',
        '0283',
        '0412',
        '0521',
        '0634',
        '0745',
        '0856',
        '0967',
        '1078',
      ],
      'cons': [
        '0041',
        '0140',
        '0283',
        '0412',
        '0521',
        '0634',
        '0745',
        '0856',
        '0967',
        '1078',
      ],
    },
  };

  test('parses dear api json for 1pm from consolation grid', () {
    final day = DateTime(2026, 6, 26);
    final data = ResultFetchService.parseDearApiJson('DEAR1', day, sampleJune26);
    expect(data, isNotNull);
    expect(data!.prizes, ['001', '770', '371', '034', '368']);
    expect(data.compliments.first, '041');
    expect(DearFastResultSource.hasFullResult(data), isTrue);
  });

  test('does not use 5th prize list when consolation grid is missing', () {
    final day = DateTime(2026, 6, 26);
    final json = Map<String, dynamic>.from(sampleJune26);
    final prizes = Map<String, dynamic>.from(json['prizes'] as Map);
    prizes.remove('cons');
    json['prizes'] = prizes;
    json['cons'] = ['20001'];

    final data = ResultFetchService.parseDearApiJson('DEAR1', day, json);
    expect(data, isNotNull);
    expect(data!.compliments.every((c) => c == '---'), isTrue);
    expect(DearFastResultSource.hasFullResult(data), isFalse);
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
