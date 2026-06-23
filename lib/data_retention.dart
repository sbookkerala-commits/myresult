import 'package:flutter/foundation.dart';

/// Bookings, sales, and results are kept for this many calendar days.
const int kDataRetentionDays = 20;

DateTime retentionCutoffDate({DateTime? at}) {
  final now = (at ?? DateTime.now()).toLocal();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(const Duration(days: kDataRetentionDays));
}

bool isWithinRetentionDate(DateTime date, {DateTime? at}) {
  final day = DateTime(date.year, date.month, date.day);
  final cutoff = retentionCutoffDate(at: at);
  return !day.isBefore(cutoff);
}
