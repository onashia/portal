import 'package:intl/intl.dart';

/// Date/time helpers for local-time conversion and display formatting.
class DateTimeUtils {
  DateTimeUtils._();

  /// Converts [value] to the user's local timezone.
  static DateTime toUserLocalTime(DateTime value) {
    return value.toLocal();
  }

  /// Formats [value] as a localized short time (for example, 7:30 PM).
  static String formatLocalJm(DateTime value) {
    final local = toUserLocalTime(value);
    return DateFormat.jm().format(local);
  }

  /// Formats [value] as a localized time with hours, minutes, and seconds.
  static String formatLocalJms(DateTime value) {
    final local = toUserLocalTime(value);
    return DateFormat.jms().format(local);
  }

  /// Formats [value] as a localized short date (for example, Feb 22, 2026).
  static String formatLocalDate(DateTime value) {
    final local = toUserLocalTime(value);
    return DateFormat.yMMMd().format(local);
  }
}
