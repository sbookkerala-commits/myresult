import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/whatsapp_booking_parser.dart';

void main() {
  group('legacy stress cases', () {
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
      expect(bookings.map((b) => b.wordOrBoard), ['SUPER', 'BOX']);
      expect(bookings.map((b) => b.quantity), [2, 3]);
    });

    test('SET keeps each generated number', () {
      final bookings = parseWhatsAppMessage('SET 123 5');
      expect(bookings.map((b) => b.itemNumber).toSet(), {
        '123',
        '132',
        '213',
        '231',
        '312',
        '321',
      });
    });
  });

  group('full parser spec', () {
    test('1D normal', () {
      expect(parseWhatsAppMessage('3.5').single.quantity, 5);
      expect(parseWhatsAppMessage('3 5').single.itemNumber, '3');
      expect(parseWhatsAppMessage('3-5').single.itemNumber, '3');
    });

    test('2D normal', () {
      final b = parseWhatsAppMessage('23.5').single;
      expect(b.itemNumber, '23');
      expect(b.quantity, 5);
    });

    test('3D normal', () {
      final b = parseWhatsAppMessage('323.5').single;
      expect(b.itemNumber, '323');
      expect(b.quantity, 5);
    });

    test('2D board inline', () {
      final ab = parseWhatsAppMessage('AB.45.5').single;
      expect(ab.wordOrBoard, 'AB');
      expect(ab.itemNumber, '45');
      expect(ab.quantity, 5);
    });

    test('1D board A B C ABC', () {
      expect(parseWhatsAppMessage('A.5.5').single.wordOrBoard, 'A');
      expect(parseWhatsAppMessage('ABC.4.5'), hasLength(3));
      expect(parseWhatsAppMessage('ALLBORD.5 10'), hasLength(3));
    });

    test('BOX and SETBOX', () {
      final box = parseWhatsAppMessage('345.box.1').single;
      expect(box.wordOrBoard, 'BOX');
      expect(box.itemNumber, '345');
      expect(parseWhatsAppMessage('345.setbox.1'), hasLength(6));
      final setbox = parseWhatsAppMessage('345.setbox.1').first;
      expect(setbox.wordOrBoard, 'SUPER');
      expect(
        parseWhatsAppMessage('345.setbox.1').every((b) => b.wordOrBoard == 'SUPER'),
        isTrue,
      );
    });

    test('vertical list trailing count', () {
      final input = '324\n677\n477\n477\n467\n577\n2';
      expect(parseWhatsAppMessage(input), hasLength(6));
      expect(parseWhatsAppMessage(input).every((b) => b.quantity == 2), isTrue);
    });

    test('grid trailing count', () {
      final input =
          '356   577  677\n555   566  567\n368   677  577\n366   467  467\n467   666  567\n2';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings.length, greaterThan(10));
      expect(bookings.every((b) => b.quantity == 2), isTrue);
    });

    test('number-count pairs', () {
      final bookings = parseWhatsAppMessage('345.10.566.10.477.10.279.10');
      expect(bookings, hasLength(4));
      expect(bookings.map((b) => b.itemNumber).toList(),
          ['345', '566', '477', '279']);
    });

    test('multiple 3d last count', () {
      final bookings = parseWhatsAppMessage('355.577.677.678.577.677.5');
      expect(bookings, hasLength(6));
      expect(bookings.every((b) => b.quantity == 5), isTrue);
    });

    test('bracket counts', () {
      final bookings = parseWhatsAppMessage('456(5)677(10)777(10)767(10)');
      expect(bookings, hasLength(4));
      expect(bookings[0].itemNumber, '456');
      expect(bookings[0].quantity, 5);
      expect(bookings[1].quantity, 10);
    });

    test('super box block', () {
      final input =
          '588.688.688.788.386.480\n987.378.466.986.778.266\n1.1';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings.where((b) => b.wordOrBoard == 'SUPER').length,
          greaterThan(10));
      expect(bookings.where((b) => b.wordOrBoard == 'BOX').length,
          greaterThan(10));
    });

    test('2D board block', () {
      final input = 'AB BC AC\n23\n65\n45\n34\n2';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings, hasLength(12));
      expect(bookings.every((b) => b.quantity == 2), isTrue);
    });

    test('mixed message', () {
      final input = '''
323.5
23.10
3.20
AB.45.5
BC.56.3
AC.57 3
A.5.5
B.4.10
ABC.4.5
345.box.1
345.setbox.1
456(5)677(10)
355.577.677.5
''';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings.length, greaterThan(15));
    });

    test('1.1 not parsed as 1D in super box context', () {
      final bookings = parseWhatsAppMessage('588.688\n1.1');
      expect(bookings.any((b) => b.wordOrBoard == 'SUPER'), isTrue);
      expect(bookings.any((b) => b.wordOrBoard == 'BOX'), isTrue);
    });

    test('WhatsApp header lines then 1+1 super box', () {
      final input =
          '[27/06, 7:04 pm] Ramshad: 256 054 256\n'
          '[27/06, 7:05 pm] Ramshad Ramshad✌️: 1+1';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings.where((b) => b.wordOrBoard == 'SUPER'), hasLength(3));
      expect(bookings.where((b) => b.wordOrBoard == 'BOX'), hasLength(3));
      expect(bookings.every((b) => b.quantity == 1), isTrue);
      expect(
        bookings.map((b) => b.itemNumber).toSet(),
        {'256', '054'},
      );
    });

    test('WhatsApp header without super box still parses numbers', () {
      final input = '[18/04, 7:54 pm] Name: 591.5';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings, hasLength(1));
      expect(bookings.single.itemNumber, '591');
    });

    test('3-digit space list not parsed as number-count pairs', () {
      final input = '256 054 256 256 246 617\n1+1';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings.where((b) => b.itemNumber == '256' && b.quantity == 54),
          isEmpty);
      expect(bookings.where((b) => b.itemNumber == '054'), isNotEmpty);
      expect(bookings.where((b) => b.wordOrBoard == 'SUPER'), hasLength(6));
      expect(bookings.where((b) => b.wordOrBoard == 'BOX'), hasLength(6));
    });

    test('clear alternating pairs still work', () {
      final bookings = parseWhatsAppMessage('345.10.566.10.477.10.279.10');
      expect(bookings, hasLength(4));
      expect(bookings.map((b) => b.itemNumber).toList(),
          ['345', '566', '477', '279']);
      expect(bookings.every((b) => b.quantity == 10), isTrue);
    });

    test('3D super box hyphen line', () {
      final bookings = parseWhatsAppMessage('941-3-3');
      expect(bookings, hasLength(2));
      expect(
        bookings.where((b) => b.itemNumber == '941' && b.wordOrBoard == 'SUPER'),
        hasLength(1),
      );
      expect(
        bookings.where((b) => b.itemNumber == '941' && b.wordOrBoard == 'BOX'),
        hasLength(1),
      );
      expect(bookings.every((b) => b.quantity == 3), isTrue);
      expect(
        bookings.where((b) => b.itemNumber == '941' && b.quantity == 3 && b.wordOrBoard == null),
        isEmpty,
      );
    });

    test('1D board hyphen line', () {
      final b = parseWhatsAppMessage('B-4-10').single;
      expect(b.wordOrBoard, 'B');
      expect(b.itemNumber, '4');
      expect(b.quantity, 10);
      final c = parseWhatsAppMessage('C-2-10').single;
      expect(c.wordOrBoard, 'C');
      expect(c.itemNumber, '2');
      expect(c.quantity, 10);
    });

    test('2D board heading block BC', () {
      final input = 'BC\n42-1\n47-1\n45-1\n46-1\n41-1';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings, hasLength(5));
      expect(bookings.every((b) => b.wordOrBoard == 'BC'), isTrue);
      expect(bookings.map((b) => b.itemNumber).toList(),
          ['42', '47', '45', '46', '41']);
      expect(bookings.every((b) => b.quantity == 1), isTrue);
    });

    test('2D board heading block AC case insensitive', () {
      final input = 'ac\n92-1\n97-1\n95-1\n96-1\n91-1';
      final bookings = parseWhatsAppMessage(input);
      expect(bookings, hasLength(5));
      expect(bookings.every((b) => b.wordOrBoard == 'AC'), isTrue);
    });

    test('slash and hash number-count separators', () {
      for (final line in ['076/3', '033/5', '076#3', '033#5', '076-3', '076.3']) {
        final b = parseWhatsAppMessage(line).single;
        expect(b.itemNumber, startsWith('0'));
        expect(b.quantity, greaterThan(0));
      }
      final slash = parseWhatsAppMessage('076/3').single;
      expect(slash.itemNumber, '076');
      expect(slash.quantity, 3);
      final hash = parseWhatsAppMessage('076#3').single;
      expect(hash.itemNumber, '076');
      expect(hash.quantity, 3);
    });

    test('set box keyword variants and separators', () {
      for (final line in [
        '059.set box 1',
        '059/set box/1',
        '059#set box#1',
        '059-set box-1',
        '059.SET BOX 1',
        '059.SetBox.1',
        '059setbox1',
        '345setbox2',
      ]) {
        final bookings = parseWhatsAppMessage(line);
        expect(bookings, hasLength(6), reason: line);
        expect(bookings.every((b) => b.wordOrBoard == 'SUPER'), isTrue, reason: line);
        expect(bookings.every((b) => b.quantity == 1) ||
                bookings.every((b) => b.quantity == 2),
            isTrue,
            reason: line);
      }
    });

    test('box keyword variants and separators', () {
      for (final line in [
        '059.box.1',
        '059/box/1',
        '059#box#1',
        '059-box-1',
        '059.BOX.1',
        '059.Box.1',
      ]) {
        final b = parseWhatsAppMessage(line).single;
        expect(b.itemNumber, '059', reason: line);
        expect(b.wordOrBoard, 'BOX', reason: line);
        expect(b.quantity, 1, reason: line);
      }
    });

    test('equals and plus number-count separators', () {
      expect(parseWhatsAppMessage('323=5').single.quantity, 5);
      expect(parseWhatsAppMessage('323=5').single.itemNumber, '323');
      expect(parseWhatsAppMessage('323*5').single.quantity, 5);
      expect(parseWhatsAppMessage('323_5').single.itemNumber, '323');
    });

    test('bracket count without closing paren', () {
      final b = parseWhatsAppMessage('345(5').single;
      expect(b.itemNumber, '345');
      expect(b.quantity, 5);
      final multi = parseWhatsAppMessage('456(5)677(10)777(10)');
      expect(multi, hasLength(3));
    });

    test('standalone 1+1 not parsed as 1D', () {
      expect(parseWhatsAppMessage('1+1'), isEmpty);
      expect(parseWhatsAppMessage('1.1'), isEmpty);
    });
  });
}
