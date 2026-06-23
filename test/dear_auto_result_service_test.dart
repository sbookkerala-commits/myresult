import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/services/dear_auto_result_service.dart';

void main() {
  group('DearAutoResultService.isAtOrAfterAutoCheck', () {
    test('DEAR1 after 1 PM IST', () {
      final at = DateTime.utc(2026, 6, 17, 7, 30); // 13:00 IST
      expect(DearAutoResultService.isAtOrAfterAutoCheck('DEAR1', at: at), isTrue);
    });

    test('DEAR1 before 1 PM IST', () {
      final at = DateTime.utc(2026, 6, 17, 6, 59); // 12:29 IST
      expect(DearAutoResultService.isAtOrAfterAutoCheck('DEAR1', at: at), isFalse);
    });

    test('DEAR6 after 6 PM IST', () {
      final at = DateTime.utc(2026, 6, 17, 12, 30); // 18:00 IST
      expect(DearAutoResultService.isAtOrAfterAutoCheck('DEAR6', at: at), isTrue);
    });
  });

  group('DearAutoResultService.mergeHybrid', () {
    test('keeps manual first prize and fills auto sections', () {
      final merged = DearAutoResultService.mergeHybrid(
        existingPrizes: ['123', '---', '---', '---', '---'],
        existingCompliments: List.filled(30, '---'),
        manualFirstPrize: true,
        incomingPrizes: ['999', '111', '222', '333', '444'],
        incomingCompliments: ['010', ...List.filled(29, '---')],
        fetchedFromWeb: true,
      );

      expect(merged.prizes[0], '123');
      expect(merged.prizes[1], '111');
      expect(merged.prizes[4], '444');
      expect(merged.compliments[0], '010');
      expect(merged.source['firstPrize'], 'manual');
      expect(merged.source['otherPrizes'], 'auto');
      expect(merged.autoStatus, 'completed');
    });

    test('does not overwrite manual first when auto has first prize', () {
      final merged = DearAutoResultService.mergeHybrid(
        existingPrizes: ['555', '---', '---', '---', '---'],
        existingCompliments: List.filled(30, '---'),
        manualFirstPrize: true,
        incomingPrizes: ['777', '111', '---', '---', '---'],
        incomingCompliments: List.filled(30, '---'),
        fetchedFromWeb: true,
      );

      expect(merged.prizes[0], '555');
      expect(merged.prizes[1], '111');
      expect(merged.autoStatus, 'waiting_for_auto_sections');
    });
  });
}
