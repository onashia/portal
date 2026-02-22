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

  /// Formats [value] as HH:mm:ss in local time.
  static String formatLocalHms(DateTime value) {
    final local = toUserLocalTime(value);
    final hours = local.hour.toString().padLeft(2, '0');
    final minutes = local.minute.toString().padLeft(2, '0');
    final seconds = local.second.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Formats [value] as a localized short date (for example, Feb 22, 2026).
  static String formatLocalDate(DateTime value) {
    final local = toUserLocalTime(value);
    return DateFormat.yMMMd().format(local);
  }
}
