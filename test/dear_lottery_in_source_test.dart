import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/services/dear_lottery_in_source.dart';

void main() {
  group('DearLotteryInSource parsing', () {
    test('parses date from page title', () {
      expect(
        DearLotteryInSource.parsePageDate(
          'Dear Lottery Result Today 1 PM | 22 June 2026',
        ),
        DateTime(2026, 6, 22),
      );
      expect(
        DearLotteryInSource.parsePageDate(
          'Dear Lottery Result Today 1 PM 6 PM 8 PM(22-6-2026)',
        ),
        DateTime(2026, 6, 22),
      );
    });

    test('extracts result image after draw heading', () {
      const html = '''
<h2>Dear Lottery Result Today 1 PM</h2>
<figure class="wp-block-image"><img src="https://dear-lottery.in/wp-content/uploads/2026/06/1000209351-2.jpg" class="wp-image-30366"/></figure>
''';
      expect(
        DearLotteryInSource.extractResultImageUrl(html, drawLabel: '1 PM'),
        'https://dear-lottery.in/wp-content/uploads/2026/06/1000209351-2.jpg',
      );
    });

    test('extracts yesterday draw images by section', () {
      const html = '''
<h2>Dear Lottery Result Yesterday 1 PM</h2>
<img src="https://dear-lottery.in/wp-content/uploads/2026/06/1000208923-1.jpg"/>
<h2>Dear Lottery Result Yesterday 6 PM</h2>
<img src="https://dear-lottery.in/wp-content/uploads/2026/06/1000209026-1.jpg"/>
<h2>Dear Lottery Result Yesterday 8 PM</h2>
<img src="https://dear-lottery.in/wp-content/uploads/2026/06/1000209099-1.jpg"/>
''';
      expect(
        DearLotteryInSource.extractResultImageUrl(html, drawLabel: '1 PM'),
        contains('1000208923'),
      );
      expect(
        DearLotteryInSource.extractResultImageUrl(html, drawLabel: '6 PM'),
        contains('1000209026'),
      );
      expect(
        DearLotteryInSource.extractResultImageUrl(html, drawLabel: '8 PM'),
        contains('1000209099'),
      );
    });
  });
}
