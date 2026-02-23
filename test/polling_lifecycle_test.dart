import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/polling_lifecycle.dart';

void main() {
  group('mergePendingRefreshState', () {
    test('merges bypass flag while always keeping pending true', () {
      final state = mergePendingRefreshState(
        currentPendingBypassRateLimit: false,
        nextBypassRateLimit: true,
      );

      expect(state.pendingRefresh, isTrue);
      expect(state.pendingBypassRateLimit, isTrue);
    });
  });

  group('shouldRequestImmediateRefresh', () {
    test('runs immediately when active, immediate, and not in-flight', () {
      final decision = shouldRequestImmediateRefresh(
        isActive: true,
        isInFlight: false,
        immediate: true,
      );

      expect(decision.shouldReconcile, isFalse);
      expect(decision.shouldQueuePending, isFalse);
      expect(decision.shouldRunNow, isTrue);
      expect(decision.shouldScheduleTick, isFalse);
    });

    test('queues pending and does not run when in-flight', () {
      final decision = shouldRequestImmediateRefresh(
        isActive: true,
        isInFlight: true,
        immediate: true,
      );

      expect(decision.shouldReconcile, isFalse);
      expect(decision.shouldQueuePending, isTrue);
      expect(decision.shouldRunNow, isFalse);
      expect(decision.shouldScheduleTick, isFalse);
    });
  });

  group('shouldScheduleNextTick', () {
    test(
      'returns true when active with no timer, no in-flight, and no pending',
      () {
        final shouldSchedule = shouldScheduleNextTick(
          isActive: true,
          hasTimer: false,
          isInFlight: false,
          hasPendingRefresh: false,
        );

        expect(shouldSchedule, isTrue);
      },
    );
  });

  group('shouldDrainPendingRefresh', () {
    test('returns true only when mounted, active, pending, and idle', () {
      final shouldDrain = shouldDrainPendingRefresh(
        isMounted: true,
        isInFlight: false,
        hasPendingRefresh: true,
        isActive: true,
      );

      expect(shouldDrain, isTrue);
    });
  });

  group('resolveCooldownAwareDelay', () {
    test('returns fallback delay when cooldown is absent', () {
      final delay = resolveCooldownAwareDelay(
        remainingCooldown: null,
        fallbackDelay: const Duration(seconds: 10),
      );

      expect(delay, const Duration(seconds: 10));
    });

    test('returns cooldown plus safety buffer when cooldown is present', () {
      final delay = resolveCooldownAwareDelay(
        remainingCooldown: const Duration(seconds: 3),
        fallbackDelay: const Duration(seconds: 10),
      );

      expect(delay, const Duration(seconds: 3, milliseconds: 250));
    });

    test('returns safety buffer when cooldown is zero or negative', () {
      final zeroDelay = resolveCooldownAwareDelay(
        remainingCooldown: Duration.zero,
        fallbackDelay: const Duration(seconds: 10),
      );
      final negativeDelay = resolveCooldownAwareDelay(
        remainingCooldown: const Duration(milliseconds: -1),
        fallbackDelay: const Duration(seconds: 10),
      );

      expect(zeroDelay, const Duration(milliseconds: 250));
      expect(negativeDelay, const Duration(milliseconds: 250));
    });

    test('supports custom safety buffer override', () {
      final delay = resolveCooldownAwareDelay(
        remainingCooldown: const Duration(milliseconds: 100),
        fallbackDelay: const Duration(seconds: 10),
        safetyBuffer: const Duration(milliseconds: 500),
      );

      expect(delay, const Duration(milliseconds: 600));
    });
  });
}
