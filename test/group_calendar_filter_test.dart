import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/calendar_event_utils.dart';

void main() {
  group('overlapsLocalDay', () {
    final day = DateTime(2026, 2, 7, 12);

    test('includes events that start before today and end today', () {
      final start = DateTime(2026, 2, 6, 23, 0);
      final end = DateTime(2026, 2, 7, 1, 0);

      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('includes events that start today and end tomorrow', () {
      final start = DateTime(2026, 2, 7, 23, 30);
      final end = DateTime(2026, 2, 8, 1, 0);

      expect(overlapsLocalDay(start: start, end: end, day: day), isTrue);
    });

    test('excludes events entirely before today', () {
      final start = DateTime(2026, 2, 6, 10, 0);
      final end = DateTime(2026, 2, 6, 12, 0);

      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });

    test('excludes events entirely after today', () {
      final start = DateTime(2026, 2, 8, 10, 0);
      final end = DateTime(2026, 2, 8, 11, 0);

      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });

    test('excludes events with inverted ranges', () {
      final start = DateTime(2026, 2, 7, 12, 0);
      final end = DateTime(2026, 2, 7, 10, 0);

      expect(overlapsLocalDay(start: start, end: end, day: day), isFalse);
    });
  });
}
