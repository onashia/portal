import 'dart:math' as math;

class TimingUtils {
  static final _random = math.Random();

  /// Returns a random delay with jitter around a base interval.
  ///
  /// [baseSeconds] - the base interval in seconds
  /// [jitterSeconds] - maximum seconds to add/subtract (range: [base-jitter, base+jitter])
  /// [minSeconds] - minimum allowed delay (default: 1)
  ///
  /// Example: base=300, jitter=60 → returns 240-360 seconds (4-6 minutes)
  static int secondsWithJitter({
    required int baseSeconds,
    required int jitterSeconds,
    int minSeconds = 1,
  }) {
    if (jitterSeconds <= 0) {
      return baseSeconds;
    }
    final delta = _random.nextInt(jitterSeconds * 2 + 1) - jitterSeconds;
    return math.max(minSeconds, baseSeconds + delta);
  }

  /// Same as secondsWithJitter but returns Duration
  static Duration durationWithJitter({
    required int baseSeconds,
    required int jitterSeconds,
    int minSeconds = 1,
  }) {
    return Duration(
      seconds: secondsWithJitter(
        baseSeconds: baseSeconds,
        jitterSeconds: jitterSeconds,
        minSeconds: minSeconds,
      ),
    );
  }

  /// Formats a timestamp as relative time from now (verbose format).
  ///
  /// Returns format: "Just now", "5 min ago", "2 hours ago", "3 days ago", or "M/D/YY"
  ///
  /// Example: 30 seconds ago → "Just now"
  /// Example: 5 minutes ago → "5 min ago"
  /// Example: 2 hours ago → "2 hours ago"
  /// Example: 3 days ago → "3 days ago"
  /// Example: 10 days ago → "10/1/26" (M/D/YY format)
  static String formatRelativeTimeVerbose(DateTime timestamp) {
    final now = DateTime.now();
    final elapsed = now.difference(timestamp);

    if (elapsed.inMinutes < 1) return 'Just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) {
      final hours = elapsed.inHours;
      return '$hours hour${hours > 1 ? 's' : ''} ago';
    }
    if (elapsed.inDays < 7) {
      final days = elapsed.inDays;
      return '$days day${days > 1 ? 's' : ''} ago';
    }

    return '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
  }
}
