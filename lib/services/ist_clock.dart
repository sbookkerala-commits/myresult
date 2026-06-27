/// India Standard Time helpers for draw schedules and result auto-fetch.
class IstClock {
  static DateTime now({DateTime? at}) {
    final ist = (at ?? DateTime.now())
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30));
    return DateTime(
      ist.year,
      ist.month,
      ist.day,
      ist.hour,
      ist.minute,
      ist.second,
    );
  }

  static DateTime calendarDay({DateTime? at}) {
    final ist = now(at: at);
    return DateTime(ist.year, ist.month, ist.day);
  }
}
