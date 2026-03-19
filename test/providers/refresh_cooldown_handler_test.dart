import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/refresh_cooldown_handler.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/portal_request_runner_common.dart';

class _FakeCooldownTracker implements PortalCooldownTracker {
  _FakeCooldownTracker({this.remaining});

  Duration? remaining;
  final List<ApiRequestLane> recordedSkips = <ApiRequestLane>[];

  @override
  Duration? remainingCooldown(ApiRequestLane lane) => remaining;

  @override
  void recordThrottledSkip({required ApiRequestLane lane}) {
    recordedSkips.add(lane);
  }
}

void main() {
  group('RefreshCooldownHandler', () {
    test('defers when cooldown is active', () {
      final tracker = _FakeCooldownTracker(
        remaining: const Duration(seconds: 30),
      );
      Duration? scheduledDelay;
      final deferred = RefreshCooldownHandler.shouldDeferForCooldown(
        cooldownTracker: tracker,
        bypassRateLimit: false,
        lane: ApiRequestLane.calendar,
        logContext: 'calendar',
        fallbackDelay: const Duration(minutes: 30),
        onDefer: (delay) => scheduledDelay = delay,
      );

      expect(deferred, isTrue);
      expect(tracker.recordedSkips, [ApiRequestLane.calendar]);
      expect(scheduledDelay, isNotNull);
    });

    test('bypass ignores active cooldown', () {
      final tracker = _FakeCooldownTracker(
        remaining: const Duration(seconds: 30),
      );
      var scheduled = false;
      final deferred = RefreshCooldownHandler.shouldDeferForCooldown(
        cooldownTracker: tracker,
        bypassRateLimit: true,
        lane: ApiRequestLane.status,
        logContext: 'vrchat_status',
        fallbackDelay: const Duration(minutes: 5),
        onDefer: (_) => scheduled = true,
      );

      expect(deferred, isFalse);
      expect(tracker.recordedSkips, isEmpty);
      expect(scheduled, isFalse);
    });

    test('does not defer when cooldown is inactive', () {
      final tracker = _FakeCooldownTracker();
      var scheduled = false;
      final deferred = RefreshCooldownHandler.shouldDeferForCooldown(
        cooldownTracker: tracker,
        bypassRateLimit: false,
        lane: ApiRequestLane.status,
        logContext: 'vrchat_status',
        fallbackDelay: const Duration(minutes: 5),
        onDefer: (_) => scheduled = true,
      );

      expect(deferred, isFalse);
      expect(tracker.recordedSkips, isEmpty);
      expect(scheduled, isFalse);
    });
  });
}
