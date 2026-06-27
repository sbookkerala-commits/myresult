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

  const sample6pmDotIn = '''
0001
0814
2022
25424  27314  37994  38114  49916
0036    0301    0750    1960    2694
26/06/26
0275    0906    2568    3458    3627
4722    4755    5092    6311    6551
87G 86392
CROWN FRIDAY
WEEKLY LOTTERY
''';

  test('parses 1pm PDF text', () {
    final day = DateTime(2026, 6, 22);
    final data = DearFastResultSource.parseDearPdfText('DEAR1', day, sample1pm);
    expect(data, isNotNull);
    expect(data!.prizes, ['432', '834', '369', '832', '065']);
    expect(data.compliments.first, '014');
    expect(DearFastResultSource.hasFullResult(data), isTrue);
  });

  test('parses dearlottery.in 6pm PDF layout without sold by', () {
    final day = DateTime(2026, 6, 26);
    final data = DearFastResultSource.parseDearPdfText('DEAR6', day, sample6pmDotIn);
    expect(data, isNotNull);
    expect(data!.prizes.take(3), ['392', '424', '036']);
    expect(data.compliments.where((c) => c != '---').length, greaterThanOrEqualTo(3));
    expect(DearFastResultSource.hasFullResult(data), isTrue);
  });

  test('rejects PDF when draw date does not match', () {
    final day = DateTime(2026, 6, 23);
    final data = DearFastResultSource.parseDearPdfText('DEAR8', day, sample1pm);
    expect(data, isNull);
  });
}
