import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/havells_shell_page.dart';

void main() {
  test('havells shell uses official website url', () {
    expect(HavellsShellPage.homeUrl, 'https://www.havells.com/');
  });
}
