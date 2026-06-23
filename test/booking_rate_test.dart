import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/price_list_store.dart';

void main() {
  test('bookingAmountFromRate preserves decimal rate', () {
    expect(bookingAmountFromRate(8.9, 1), closeTo(8.9, 0.001));
    expect(bookingAmountFromRate(8.9, 2), closeTo(17.8, 0.001));
    expect(bookingAmountFromRate(8.9, 3), closeTo(26.7, 0.001));
  });

  test('readBookingRate never truncates to int', () {
    expect(readBookingRate(8.9), 8.9);
    expect(readBookingRate('8.9'), 8.9);
    expect(readBookingRate(9), 9.0);
  });

  test('coerceSchemeRate keeps decimals from price list', () {
    expect(
      coerceSchemeRate(8.9, 'DEAR1-SUPER'),
      8.9,
    );
    expect(
      coerceSchemeRate('8.9', 'DEAR1-SUPER'),
      8.9,
    );
  });
}
