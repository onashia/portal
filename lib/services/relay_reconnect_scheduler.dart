import 'dart:async';
import 'dart:math' as math;

/// Schedules reconnection attempts with exponential backoff and jitter.
///
/// Each call to [schedule] increments the internal attempt counter and
/// computes a delay in the range `[base * 2^(n-1) * 0.75, base * 2^(n-1)]`,
/// capped at [maxSeconds]. Call [reset] after a successful connection to
/// restart from the shortest delay on the next disconnection.
class ReconnectScheduler {
  ReconnectScheduler({
    required math.Random random,
    required int baseSeconds,
    required int maxSeconds,
  }) : _random = random,
       _baseSeconds = baseSeconds,
       _maxSeconds = maxSeconds;

  final math.Random _random;
  final int _baseSeconds;
  final int _maxSeconds;

  Timer? _timer;
  int _attempt = 0;

  /// The number of reconnection attempts made since the last [reset].
  int get attemptCount => _attempt;

  /// Schedules [callback] to be called after an exponentially backed-off delay.
  ///
  /// Any previously scheduled reconnect is cancelled first.
  void schedule(void Function() callback) {
    _timer?.cancel();
    _attempt += 1;
    final delay = Duration(seconds: _nextDelaySeconds());
    _timer = Timer(delay, callback);
  }

  /// Cancels any pending reconnect.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Resets the attempt counter so the next reconnect uses the minimum delay.
  ///
  /// Call this after a successful connection.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _attempt = 0;
  }

  int _nextDelaySeconds() {
    final exponent = _attempt.clamp(1, 6);
    final exponentialBase = _baseSeconds * (1 << (exponent - 1));
    final capped = math.min(exponentialBase, _maxSeconds);
    final lowerBound = math.max(1, (capped * 3) ~/ 4);
    // lowerBound <= capped always holds (lowerBound = max(1, capped*3/4)),
    // so capped - lowerBound + 1 >= 1 and nextInt never receives 0.
    return lowerBound + _random.nextInt(capped - lowerBound + 1);
  }
}
