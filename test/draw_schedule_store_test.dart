import 'package:flutter_test/flutter_test.dart';
import 'package:sbook_lottery/draw_schedule_store.dart';

void main() {
  setUp(() {
    DrawScheduleStore.schedules.value = {
      for (final name in kDrawTimeNames)
        name: DrawScheduleStore.scheduleFor(name),
    };
  });

  test('before admin close → today business date', () {
    DrawScheduleStore.schedules.value = {
      ...DrawScheduleStore.schedules.value,
      'DEAR 8 PM': const DrawSchedule(
        drawTime: 'DEAR 8 PM',
        openHour: 7,
        openMinute: 0,
        closeHour: 22,
        closeMinute: 0,
      ),
    };
    expect(
      DrawScheduleStore.businessDateForDraw(
        'DEAR 8 PM',
        at: DateTime(2026, 6, 22, 21, 59),
      ),
      DateTime(2026, 6, 22),
    );
  });

  test('after admin close → next business date', () {
    DrawScheduleStore.schedules.value = {
      ...DrawScheduleStore.schedules.value,
      'DEAR 8 PM': const DrawSchedule(
        drawTime: 'DEAR 8 PM',
        openHour: 7,
        openMinute: 0,
        closeHour: 22,
        closeMinute: 0,
      ),
    };
    expect(
      DrawScheduleStore.businessDateForDraw(
        'DEAR 8 PM',
        at: DateTime(2026, 6, 22, 22, 1),
      ),
      DateTime(2026, 6, 23),
    );
    expect(
      DrawScheduleStore.currentBusinessDate(
        at: DateTime(2026, 6, 22, 22, 1),
      ),
      DateTime(2026, 6, 23),
    );
  });

  test('overnight schedule evening → next business date', () {
    DrawScheduleStore.schedules.value = {
      ...DrawScheduleStore.schedules.value,
      'DEAR 1 PM': const DrawSchedule(
        drawTime: 'DEAR 1 PM',
        openHour: 17,
        openMinute: 0,
        closeHour: 13,
        closeMinute: 0,
      ),
    };
    expect(
      DrawScheduleStore.businessDateForDraw(
        'DEAR 1 PM',
        at: DateTime(2026, 6, 22, 18, 0),
      ),
      DateTime(2026, 6, 23),
    );
    expect(
      DrawScheduleStore.businessDateForDraw(
        'DEAR 1 PM',
        at: DateTime(2026, 6, 23, 10, 0),
      ),
      DateTime(2026, 6, 23),
    );
  });

  test('all draws follow close-time rule', () {
    for (final draw in kDrawTimeNames) {
      final s = DrawScheduleStore.scheduleFor(draw);
      if (s.openHour * 60 + s.openMinute > s.closeHour * 60 + s.closeMinute) {
        continue;
      }
      final beforeClose = DateTime(2026, 6, 22, s.closeHour, s.closeMinute);
      final afterClose = beforeClose.add(const Duration(minutes: 1));
      expect(
        DrawScheduleStore.businessDateForDraw(draw, at: beforeClose),
        DateTime(2026, 6, 22),
      );
      expect(
        DrawScheduleStore.businessDateForDraw(draw, at: afterClose),
        DateTime(2026, 6, 23),
      );
    }
  });

  test('DEAR 1 PM open 9PM close 12:59 PM evening booking → next day', () {
    DrawScheduleStore.schedules.value = {
      ...DrawScheduleStore.schedules.value,
      'DEAR 1 PM': const DrawSchedule(
        drawTime: 'DEAR 1 PM',
        openHour: 21,
        openMinute: 0,
        closeHour: 12,
        closeMinute: 59,
      ),
    };
    expect(
      DrawScheduleStore.businessDateForDraw(
        'DEAR 1 PM',
        at: DateTime(2026, 6, 22, 21, 30),
      ),
      DateTime(2026, 6, 23),
    );
  });
}
