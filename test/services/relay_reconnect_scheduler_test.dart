import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/services/relay_reconnect_scheduler.dart';

class _FixedRandom implements math.Random {
  _FixedRandom(this._value);

  final int _value;

  @override
  bool nextBool() => _value.isOdd;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => _value.clamp(0, max - 1);
}

/// Schedules [attempt] callbacks on a fresh [ReconnectScheduler] and returns
/// how many whole seconds elapsed before the final callback fired.
///
/// Each earlier schedule() call is superseded by the next, so only the timer
/// for [attempt] is pending when [fakeAsync] starts advancing time. The random
/// object is shared so its state carries across setup calls, matching the
/// real-world behaviour of a long-lived scheduler instance.
int _measureDelaySeconds({
  required int attempt,
  required math.Random random,
  int baseSeconds = AppConstants.relayReconnectBaseSeconds,
  int maxSeconds = AppConstants.relayReconnectMaxSeconds,
}) {
  var result = 0;
  fakeAsync((async) {
    final scheduler = ReconnectScheduler(
      random: random,
      baseSeconds: baseSeconds,
      maxSeconds: maxSeconds,
    );
    for (var i = 1; i < attempt; i++) {
      scheduler.schedule(() {});
    }
    var fired = false;
    scheduler.schedule(() {
      fired = true;
    });
    for (var s = 1; s <= maxSeconds + 5; s++) {
      async.elapse(const Duration(seconds: 1));
      if (fired) {
        result = s;
        return;
      }
    }
    fail('Reconnect callback never fired for attempt $attempt');
  });
  return result;
}

void main() {
  group('ReconnectScheduler', () {
    group('behaviour', () {
      test('schedule_fires_callback_after_computed_delay', () {
        // Attempt 1 with fixed-min random: lowerBound=1, so delay=1s.
        fakeAsync((async) {
          final scheduler = ReconnectScheduler(
            random: _FixedRandom(0),
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
          );
          var fired = false;
          scheduler.schedule(() {
            fired = true;
          });

          async.elapse(const Duration(milliseconds: 999));
          expect(fired, isFalse, reason: 'must not fire before the 1s delay');
          async.elapse(const Duration(milliseconds: 1));
          expect(
            fired,
            isTrue,
            reason: 'must fire at exactly 1s for attempt 1',
          );
        });
      });

      test('schedule_cancels_previous_pending_timer', () {
        fakeAsync((async) {
          final scheduler = ReconnectScheduler(
            random: _FixedRandom(0),
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
          );
          var firstFired = false;
          var secondFired = false;

          // First schedule (attempt 1, delay 1s).
          scheduler.schedule(() {
            firstFired = true;
          });
          // Re-schedule (attempt 2, delay 3s) before first fires.
          scheduler.schedule(() {
            secondFired = true;
          });

          // Advance well past attempt 1's delay (1s) but before attempt 2 (3s).
          async.elapse(const Duration(seconds: 2));
          expect(
            firstFired,
            isFalse,
            reason: 'first timer must have been cancelled',
          );
          expect(secondFired, isFalse);

          // Advance past attempt 2's delay.
          async.elapse(const Duration(seconds: 2));
          expect(secondFired, isTrue);
        });
      });

      test('cancel_prevents_callback_from_firing', () {
        fakeAsync((async) {
          final scheduler = ReconnectScheduler(
            random: _FixedRandom(0),
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
          );
          var fired = false;
          scheduler.schedule(() {
            fired = true;
          });
          scheduler.cancel();

          async.elapse(const Duration(seconds: 10));
          expect(fired, isFalse);
        });
      });

      test('reset_zeroes_attempt_count_and_cancels_timer', () {
        fakeAsync((async) {
          final scheduler = ReconnectScheduler(
            random: _FixedRandom(0),
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
          );
          var firstFired = false;
          var secondFired = false;

          scheduler.schedule(() {
            firstFired = true;
          });
          scheduler.schedule(() {});
          expect(scheduler.attemptCount, 2);

          scheduler.reset();
          expect(scheduler.attemptCount, 0);

          // After reset, the next schedule starts from attempt 1 (delay 1s).
          scheduler.schedule(() {
            secondFired = true;
          });
          expect(scheduler.attemptCount, 1);

          // Advance just under 1s — must not fire.
          async.elapse(const Duration(milliseconds: 999));
          expect(
            firstFired,
            isFalse,
            reason: 'previous timer must be cancelled',
          );
          expect(secondFired, isFalse);

          async.elapse(const Duration(milliseconds: 1));
          expect(secondFired, isTrue);
        });
      });

      test('attempt_count_increments_on_each_schedule', () {
        fakeAsync((async) {
          final scheduler = ReconnectScheduler(
            random: _FixedRandom(0),
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
          );
          expect(scheduler.attemptCount, 0);
          scheduler.schedule(() {});
          expect(scheduler.attemptCount, 1);
          scheduler.schedule(() {});
          expect(scheduler.attemptCount, 2);
          scheduler.schedule(() {});
          expect(scheduler.attemptCount, 3);
        });
      });

      test('cancel_leaves_attempt_count_unchanged', () {
        fakeAsync((async) {
          final scheduler = ReconnectScheduler(
            random: _FixedRandom(0),
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
          );
          scheduler.schedule(() {});
          scheduler.schedule(() {});
          expect(scheduler.attemptCount, 2);
          scheduler.cancel();
          // cancel() clears the pending timer but does not reset attempt count.
          expect(scheduler.attemptCount, 2);
        });
      });
    });

    group('backoff ranges', () {
      test('stays_within_expected_ranges_by_reconnect_attempt', () {
        final expectedRanges = <int, ({int min, int max})>{
          1: (min: 1, max: 2),
          2: (min: 3, max: 4),
          3: (min: 6, max: 8),
          4: (min: 12, max: 16),
          5: (min: 15, max: 20),
          6: (min: 15, max: 20),
        };

        for (final entry in expectedRanges.entries) {
          final delay = _measureDelaySeconds(
            attempt: entry.key,
            random: math.Random(entry.key),
          );
          expect(
            delay,
            inInclusiveRange(entry.value.min, entry.value.max),
            reason:
                'attempt ${entry.key} expected [${entry.value.min}, ${entry.value.max}]',
          );
        }
      });

      test('never_exceeds_the_configured_max_delay', () {
        final random = math.Random(42);
        for (var attempt = 1; attempt <= 30; attempt += 1) {
          for (var run = 0; run < 10; run += 1) {
            final delay = _measureDelaySeconds(
              attempt: attempt,
              random: random,
            );
            expect(
              delay,
              lessThanOrEqualTo(AppConstants.relayReconnectMaxSeconds),
              reason: 'attempt $attempt run $run exceeded max delay',
            );
            expect(delay, greaterThanOrEqualTo(1));
          }
        }
      });

      test('keeps_non_trivial_jitter_spread_when_delay_is_capped', () {
        final random = math.Random(7);
        final delays = <int>{};
        for (var run = 0; run < 30; run += 1) {
          delays.add(_measureDelaySeconds(attempt: 8, random: random));
        }

        expect(
          delays.every((d) => d >= 15 && d <= 20),
          isTrue,
          reason: 'all delays must be within capped jitter range [15, 20]',
        );
        expect(
          delays.length,
          greaterThan(1),
          reason: 'jitter must produce multiple distinct delays',
        );
      });
    });
  });
}
