/// Tracks deduplication windows for keyed entries by recording expiry times.
///
/// Keys are blocked (i.e. considered duplicates) until the recorded TTL window
/// elapses. Entries can be pruned periodically to avoid unbounded memory growth.
class DedupeTracker {
  final Map<String, DateTime> _seenUntilByKey = <String, DateTime>{};

  /// Returns true if [key] is within a previously recorded deduplication window.
  bool isBlocked(String key, DateTime now) {
    return _seenUntilByKey[key]?.isAfter(now) == true;
  }

  /// Records [key] as seen, blocking it for [ttl] starting from [now].
  ///
  /// Re-recording an existing key extends (replaces) its window.
  void record(String key, {required DateTime now, required Duration ttl}) {
    _seenUntilByKey[key] = now.add(ttl);
  }

  /// Removes all entries whose windows have expired at [now].
  void prune(DateTime now) {
    _seenUntilByKey.removeWhere((_, until) => !until.isAfter(now));
  }
}
