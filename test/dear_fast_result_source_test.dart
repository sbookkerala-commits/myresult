import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/services/dear_fast_result_source.dart';

void main() {
  const sample1pm = '''
0014076316902497412347655569688777118891
0020079418122832422648995582694878868920
Sold by : SELLER
22834  40248  42754  44931  46579
48941  49576  50142  70267  87395
1369    3988    6585    6978    6999
8264    8299    8315    8618    8674
22/06/26
3832    5065    5620    5681    5729
5950    6646    7827    8547    9748
49L 80432
WEEKLY LOTTERY
5thPrize Amount
''';

  test('parses 1pm PDF text', () {
    final day = DateTime(2026, 6, 22);
    final data = DearFastResultSource.parseDearPdfText('DEAR1', day, sample1pm);
    expect(data, isNotNull);
    final joined = sample1pm.replaceAll('\n', ' ');
    final matches = RegExp(r'(\d{1,2}[A-Z])\s+(\d{5})')
        .allMatches(joined)
        .map((m) => m.group(0))
        .toList();
    expect(matches, contains('49L 80432'));
    expect(data!.prizes, ['432', '834', '369', '832', '065']);
    expect(data.compliments.first, '014');
    expect(DearFastResultSource.hasFullResult(data), isTrue);
  });

  test('rejects PDF when draw date does not match', () {
    final day = DateTime(2026, 6, 23);
    final data = DearFastResultSource.parseDearPdfText('DEAR8', day, sample1pm);
    expect(data, isNull);
  });
}
