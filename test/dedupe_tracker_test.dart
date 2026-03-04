import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/group_monitor_provider.dart';

void main() {
  group('DedupeTracker', () {
    final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
    const ttl = Duration(minutes: 5);

    test('isBlocked returns false for unknown key', () {
      final tracker = DedupeTracker();

      expect(tracker.isBlocked('key', t0), isFalse);
    });

    test('isBlocked returns true immediately after record within TTL', () {
      final tracker = DedupeTracker();
      tracker.record('key', now: t0, ttl: ttl);

      expect(tracker.isBlocked('key', t0), isTrue);
      expect(
        tracker.isBlocked('key', t0.add(ttl - const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('isBlocked returns false after TTL expires', () {
      final tracker = DedupeTracker();
      tracker.record('key', now: t0, ttl: ttl);

      expect(tracker.isBlocked('key', t0.add(ttl)), isFalse);
      expect(
        tracker.isBlocked('key', t0.add(ttl + const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('re-recording the same key extends the window', () {
      final tracker = DedupeTracker();
      tracker.record('key', now: t0, ttl: ttl);

      final t1 = t0.add(const Duration(minutes: 3));
      tracker.record('key', now: t1, ttl: ttl);

      // Would have expired at t0 + 5m, but re-recorded at t1 so expires at t1 + 5m
      expect(tracker.isBlocked('key', t0.add(ttl)), isTrue);
      expect(
        tracker.isBlocked('key', t1.add(ttl - const Duration(seconds: 1))),
        isTrue,
      );
      expect(tracker.isBlocked('key', t1.add(ttl)), isFalse);
    });

    test('prune removes expired entries and leaves live entries', () {
      final tracker = DedupeTracker();
      tracker.record('expired', now: t0, ttl: const Duration(minutes: 1));
      tracker.record('live', now: t0, ttl: ttl);

      final pruneTime = t0.add(const Duration(minutes: 2));
      tracker.prune(pruneTime);

      expect(tracker.isBlocked('expired', pruneTime), isFalse);
      expect(tracker.isBlocked('live', pruneTime), isTrue);
    });

    test('different keys are tracked independently', () {
      final tracker = DedupeTracker();
      tracker.record('a', now: t0, ttl: ttl);

      expect(tracker.isBlocked('a', t0), isTrue);
      expect(tracker.isBlocked('b', t0), isFalse);
    });
  });
}
