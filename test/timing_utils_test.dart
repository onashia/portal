import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/timing_utils.dart';

void main() {
  group('formatRelativeTimeVerbose', () {
    test('returns "Just now" for timestamps less than 1 minute ago', () {
      final timestamp = DateTime.now().subtract(const Duration(seconds: 30));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, 'Just now');
    });

    test('returns "Just now" for timestamps exactly at now', () {
      final timestamp = DateTime.now();
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, 'Just now');
    });

    test('returns "X min ago" for timestamps in minutes (singular)', () {
      final timestamp = DateTime.now().subtract(const Duration(minutes: 1));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, '1 min ago');
    });

    test('returns "X min ago" for timestamps in minutes (plural)', () {
      final timestamp = DateTime.now().subtract(const Duration(minutes: 5));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, '5 min ago');
    });

    test('returns "X hour ago" for timestamps in hours (singular)', () {
      final timestamp = DateTime.now().subtract(const Duration(hours: 1));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, '1 hour ago');
    });

    test('returns "X hours ago" for timestamps in hours (plural)', () {
      final timestamp = DateTime.now().subtract(const Duration(hours: 3));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, '3 hours ago');
    });

    test('returns "X day ago" for timestamps in days (singular)', () {
      final timestamp = DateTime.now().subtract(const Duration(days: 1));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, '1 day ago');
    });

    test('returns "X days ago" for timestamps in days (plural)', () {
      final timestamp = DateTime.now().subtract(const Duration(days: 3));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, '3 days ago');
    });

    test('returns M/D/YY format for timestamps 7 or more days ago', () {
      final timestamp = DateTime.now().subtract(const Duration(days: 10));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      final expected =
          '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
      expect(result, expected);
    });

    test('handles future timestamps (returns Just now)', () {
      final timestamp = DateTime.now().add(const Duration(hours: 1));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, 'Just now');
    });

    test('handles exactly 1 day boundary', () {
      final timestamp = DateTime.now().subtract(
        const Duration(days: 1, hours: 23, minutes: 59),
      );
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      expect(result, '1 day ago');
    });

    test('handles exactly 7 day boundary (uses date format)', () {
      final timestamp = DateTime.now().subtract(const Duration(days: 7));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      final expected =
          '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
      expect(result, expected);
    });

    test('handles year rollover in date format', () {
      final timestamp = DateTime.now().subtract(const Duration(days: 400));
      final result = TimingUtils.formatRelativeTimeVerbose(timestamp);
      final expected =
          '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
      expect(result, expected);
    });
  });
}
