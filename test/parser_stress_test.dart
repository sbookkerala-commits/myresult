import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/whatsapp_booking_parser.dart';

void main() {
  final testCases = <({String name, String input, int expectedCount})>[
    (name: 'Basic format', input: '123-5', expectedCount: 1),
    (name: 'SUPER and BOX quantities', input: '374.2.2', expectedCount: 2),
    (
      name: 'Ticket run with trailing quantity',
      input: '111.222.333.444.10',
      expectedCount: 4,
    ),
    (
      name: 'Vertical digit lines with trailing quantity',
      input: '111\n222\n333\n10',
      expectedCount: 3,
    ),
    (name: 'SET permutations', input: 'SET 123 5', expectedCount: 6),
    (
      name: 'Sticky board label',
      input: 'BC\n11.10\n22.10',
      expectedCount: 2,
    ),
    (name: 'ABC shortcut', input: 'ABC 1-5', expectedCount: 3),
    (
      name: 'WhatsApp timestamp removal',
      input: '[18/04, 7:54 pm] Name: 591.5',
      expectedCount: 1,
    ),
  ];

  for (final testCase in testCases) {
    test(testCase.name, () {
      final bookings = parseWhatsAppMessage(testCase.input);
      expect(bookings, hasLength(testCase.expectedCount));
    });
  }

  test('split entry assigns SUPER and BOX labels', () {
    final bookings = parseWhatsAppMessage('374.2.3');

    expect(bookings.map((booking) => booking.wordOrBoard), ['SUPER', 'BOX']);
    expect(bookings.map((booking) => booking.quantity), [2, 3]);
  });

  test('SET keeps each generated number', () {
    final bookings = parseWhatsAppMessage('SET 123 5');

    expect(bookings.map((booking) => booking.itemNumber).toSet(), {
      '123',
      '132',
      '213',
      '231',
      '312',
      '321',
    });
  });
}
