import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/calendar_event_utils.dart';

void main() {
  group('startOfLocalDay', () {
    test('returns midnight for local date', () {
      final result = startOfLocalDay(DateTime(2024, 1, 15));
      expect(result, DateTime(2024, 1, 15, 0, 0, 0, 0));
    });

    test('handles UTC date that doesn\'t cross day boundary', () {
      final utcDate = DateTime.utc(2024, 3, 20, 15, 30);
      final result = startOfLocalDay(utcDate);
      // Should convert to local then return midnight
      final localDate = utcDate.toLocal();
      final expected = DateTime(localDate.year, localDate.month, localDate.day);
      expect(result, expected);
    });

    test('handles local date input correctly', () {
      final localDate = DateTime(2024, 6, 10, 12, 30, 45);
      final result = startOfLocalDay(localDate);
      expect(result, DateTime(2024, 6, 10, 0, 0, 0, 0));
    });

    test('handles different months', () {
      for (var month = 1; month <= 12; month++) {
        final result = startOfLocalDay(DateTime(2024, month, 15));
        expect(result, DateTime(2024, month, 15, 0, 0, 0, 0));
      }
    });

    test('handles different years', () {
      for (final year in [2020, 2024, 2025, 2026]) {
        final result = startOfLocalDay(DateTime(year, 6, 15));
        expect(result, DateTime(year, 6, 15, 0, 0, 0, 0));
      }
    });

    test('handles leap day (Feb 29)', () {
      final result = startOfLocalDay(DateTime(2024, 2, 29));
      expect(result, DateTime(2024, 2, 29, 0, 0, 0, 0));
    });

    test('handles January 31', () {
      final result = startOfLocalDay(DateTime(2024, 1, 31));
      expect(result, DateTime(2024, 1, 31, 0, 0, 0, 0));
    });

    test('handles December 31', () {
      final result = startOfLocalDay(DateTime(2024, 12, 31));
      expect(result, DateTime(2024, 12, 31, 0, 0, 0, 0));
    });
  });

  group('endOfLocalDay', () {
    test('returns 23:59:59.999 for local date', () {
      final result = endOfLocalDay(DateTime(2024, 1, 15));
      final expected = DateTime(
        2024,
        1,
        16,
      ).subtract(const Duration(milliseconds: 1));
      expect(result, expected);
    });

    test('is one millisecond before next day', () {
      final day = DateTime(2024, 3, 20);
      final nextDay = DateTime(2024, 3, 21);
      final result = endOfLocalDay(day);
      expect(result.difference(nextDay), const Duration(milliseconds: -1));
    });

    test('handles UTC date that doesn\'t cross day boundary', () {
      final utcDate = DateTime.utc(2024, 6, 10, 8, 0);
      final result = endOfLocalDay(utcDate);
      // Should convert to local then return end of local day
      final localDate = utcDate.toLocal();
      final expected = DateTime(
        localDate.year,
        localDate.month,
        localDate.day + 1,
      ).subtract(const Duration(milliseconds: 1));
      expect(result, expected);
    });

    test('handles local date input correctly', () {
      final localDate = DateTime(2024, 9, 15, 14, 20, 30);
      final result = endOfLocalDay(localDate);
      final expected = DateTime(
        2024,
        9,
        16,
      ).subtract(const Duration(milliseconds: 1));
      expect(result, expected);
    });

    test('handles different months', () {
      for (var month = 1; month <= 12; month++) {
        final result = endOfLocalDay(DateTime(2024, month, 10));
        final expected = startOfLocalDay(DateTime(2024, month, 10))
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
        expect(result, expected);
      }
    });

    test('handles December 31 (end of year)', () {
      final result = endOfLocalDay(DateTime(2024, 12, 31));
      final expected = startOfLocalDay(
        DateTime(2024, 12, 31),
      ).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      expect(result, expected);
    });

    test('is consistent with startOfLocalDay + 1 day - 1ms', () {
      final day = DateTime(2024, 7, 4);
      final start = startOfLocalDay(day);
      final end = endOfLocalDay(day);
      final expected = start
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1));
      expect(end, expected);
    });

    test('handles leap day (Feb 29)', () {
      final result = endOfLocalDay(DateTime(2024, 2, 29));
      final expected = startOfLocalDay(
        DateTime(2024, 2, 29),
      ).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      expect(result, expected);
    });
  });

  group('overlapsLocalDay', () {
    test('event entirely within day returns true', () {
      final day = DateTime(2024, 1, 15);
      final start = DateTime(2024, 1, 15, 10, 0);
      final end = DateTime(2024, 1, 15, 14, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('event starts before day, ends within day returns true', () {
      final day = DateTime(2024, 2, 20);
      final start = DateTime(2024, 2, 19, 22, 0);
      final end = DateTime(2024, 2, 20, 8, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('event starts within day, ends after day returns true', () {
      final day = DateTime(2024, 3, 10);
      final start = DateTime(2024, 3, 10, 18, 0);
      final end = DateTime(2024, 3, 11, 2, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('event spanning entire day returns true', () {
      final day = DateTime(2024, 4, 5);
      final start = DateTime(2024, 4, 4, 12, 0);
      final end = DateTime(2024, 4, 6, 12, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('multi-day event overlapping target day returns true', () {
      final day = DateTime(2024, 5, 15);
      final start = DateTime(2024, 5, 13, 0, 0);
      final end = DateTime(2024, 5, 20, 23, 59);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('event entirely before day returns false', () {
      final day = DateTime(2024, 6, 15);
      final start = DateTime(2024, 6, 10, 10, 0);
      final end = DateTime(2024, 6, 10, 14, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });

    test('event entirely after day returns false', () {
      final day = DateTime(2024, 7, 10);
      final start = DateTime(2024, 7, 20, 10, 0);
      final end = DateTime(2024, 7, 20, 14, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });

    test('event starts at next day start returns false', () {
      final day = DateTime(2024, 7, 10);
      final start = startOfLocalDay(day).add(const Duration(days: 1));
      final end = DateTime(2024, 7, 21, 10, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });

    test('event end at day start (inclusive boundary)', () {
      final day = DateTime(2024, 8, 15);
      final start = DateTime(2024, 8, 14, 10, 0);
      final end = startOfLocalDay(day);
      // End at day start overlaps (inclusive boundary)
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('event start at day end (inclusive boundary)', () {
      final day = DateTime(2024, 9, 20);
      final start = endOfLocalDay(day);
      final end = DateTime(2024, 9, 21, 10, 0);
      // Start at day end overlaps (inclusive boundary)
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('event entirely before day (ends at previous day end)', () {
      final day = DateTime(2024, 9, 21);
      final start = DateTime(2024, 9, 20, 10, 0);
      final end = endOfLocalDay(day.subtract(const Duration(days: 1)));
      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });

    test('event starting at day start returns true', () {
      final day = DateTime(2024, 10, 5);
      final start = startOfLocalDay(day);
      final end = DateTime(2024, 10, 5, 10, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('event ending at day end returns true', () {
      final day = DateTime(2024, 11, 12);
      final start = DateTime(2024, 11, 12, 18, 0);
      final end = endOfLocalDay(day);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('zero-duration event in middle of day returns true', () {
      final day = DateTime(2024, 1, 15);
      final start = DateTime(2024, 1, 15, 10, 0);
      final end = DateTime(2024, 1, 15, 10, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test(
      'zero-duration event at day start returns true (inclusive boundary)',
      () {
        final day = DateTime(2024, 1, 15);
        final start = startOfLocalDay(day);
        final end = startOfLocalDay(day);
        expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
      },
    );

    test('zero-duration event just before day start returns false', () {
      final day = DateTime(2024, 1, 15);
      final start = startOfLocalDay(
        day,
      ).subtract(const Duration(milliseconds: 1));
      final end = startOfLocalDay(
        day,
      ).subtract(const Duration(milliseconds: 1));
      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });

    test(
      'zero-duration event at day end returns true (inclusive boundary)',
      () {
        final day = DateTime(2024, 1, 15);
        final start = endOfLocalDay(day);
        final end = endOfLocalDay(day);
        expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
      },
    );

    test('event end before start returns false (invalid)', () {
      final day = DateTime(2024, 12, 15);
      final start = DateTime(2024, 12, 15, 14, 0);
      final end = DateTime(2024, 12, 15, 10, 0);
      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });
  });
}
