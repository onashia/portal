import 'dart:async';

/// Manages the WebSocket heartbeat ping/pong cycle and stale-connection
/// detection for the relay assist service.
///
/// The monitor sends a periodic ping and tracks the last time a pong was
/// received. If no pong arrives within [staleAfter] of the last recorded
/// acknowledgement, [onStale] is invoked so the caller can reconnect.
class RelayHeartbeatMonitor {
  RelayHeartbeatMonitor({
    Duration? interval,
    Duration? staleAfter,
    DateTime Function()? now,
  }) : _interval =
           interval ??
           const Duration(seconds: _kDefaultHeartbeatIntervalSeconds),
       _staleAfter =
           staleAfter ??
           const Duration(seconds: _kDefaultHeartbeatStaleSeconds),
       _now = now ?? DateTime.now;

  static const int _kDefaultHeartbeatIntervalSeconds = 20;
  static const int _kDefaultHeartbeatStaleSeconds = 60;

  final Duration _interval;
  final Duration _staleAfter;
  final DateTime Function() _now;

  Timer? _timer;
  DateTime? _lastPongAt;

  /// The timestamp of the most recent pong received, or null if none yet.
  DateTime? get lastPongAt => _lastPongAt;

  /// Whether the connection is considered stale based on the last pong time.
  ///
  /// Returns `true` if the monitor has not been started (no pong has ever been
  /// recorded) or if the last pong was received more than [_staleAfter] ago.
  /// Note: [start] seeds [_lastPongAt] with the current time before the first
  /// tick fires, so a freshly started monitor is not immediately stale.
  bool get isStale {
    final last = _lastPongAt;
    if (last == null) {
      return true;
    }
    return !last.add(_staleAfter).isAfter(_now());
  }

  /// Starts the heartbeat timer.
  ///
  /// [sendPing] is called every [interval] to send a ping frame.
  /// [onStale] is called when no pong has been received within [staleAfter].
  void start({
    required void Function(DateTime now) sendPing,
    required void Function() onStale,
  }) {
    stop();
    final startPongAt = _now();
    _lastPongAt = startPongAt;
    _timer = Timer.periodic(_interval, (_) {
      final now = _now();
      if (isStale) {
        stop();
        onStale();
        return;
      }
      sendPing(now);
    });
  }

  /// Records a received pong, resetting the stale-detection window.
  void recordPong() {
    _lastPongAt = _now();
  }

  /// Cancels the heartbeat timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
