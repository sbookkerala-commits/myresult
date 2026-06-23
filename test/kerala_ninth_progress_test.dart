import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/kerala_compliment_rules.dart';

void main() {
  test('9th incomplete when count below declared N', () {
    const declared = 144;
    final partial = List.generate(100, (i) => i.toString().padLeft(4, '0'));
    expect(
      KeralaComplimentRules.ninthIsComplete(partial, declared),
      isFalse,
    );
  });

  test('9th incomplete without declared N', () {
    final full = List.generate(144, (i) => i.toString().padLeft(4, '0'));
    expect(KeralaComplimentRules.ninthIsComplete(full, null), isFalse);
  });

  test('9th complete at declared N', () {
    const declared = 144;
    final full = List.generate(144, (i) => i.toString().padLeft(4, '0'));
    expect(
      KeralaComplimentRules.ninthIsComplete(full, declared),
      isTrue,
    );
  });

  test('filter keeps 1000 in 9th grid', () {
    final out = KeralaComplimentRules.filterNinthGridNumbers(['1000', '8377', '2000']);
    expect(out, ['1000']);
  });
}
