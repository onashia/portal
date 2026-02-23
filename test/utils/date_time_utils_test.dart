import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:portal/utils/date_time_utils.dart';

void main() {
  group('DateTimeUtils.toUserLocalTime', () {
    test('converts UTC timestamps to local time', () {
      final utc = DateTime.utc(2026, 2, 13, 14, 15, 16);

      final result = DateTimeUtils.toUserLocalTime(utc);

      expect(result, utc.toLocal());
      expect(result.isUtc, isFalse);
    });

    test('preserves local timestamp values', () {
      final local = DateTime(2026, 2, 13, 9, 8, 7);

      final result = DateTimeUtils.toUserLocalTime(local);

      expect(result, local);
      expect(result.isUtc, isFalse);
    });
  });

  group('DateTimeUtils.formatLocalJm', () {
    test('matches intl short-time format of local-converted value', () {
      final utc = DateTime.utc(2026, 2, 13, 14, 15, 16);

      final expected = DateFormat.jm().format(utc.toLocal());
      final actual = DateTimeUtils.formatLocalJm(utc);

      expect(actual, expected);
    });
  });

  group('DateTimeUtils.formatLocalJms', () {
    test('matches intl time format with seconds of local-converted value', () {
      final utc = DateTime.utc(2026, 2, 13, 14, 15, 16);

      final expected = DateFormat.jms().format(utc.toLocal());
      final actual = DateTimeUtils.formatLocalJms(utc);

      expect(actual, expected);
    });
  });
}
