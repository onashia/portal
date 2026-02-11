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
}
