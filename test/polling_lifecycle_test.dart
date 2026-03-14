import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

  group('RefreshLoopState', () {
    test('queuePending merges bypass flag using OR semantics', () {
      final loop = RefreshLoopState();

      loop.queuePending(bypassRateLimit: false);
      expect(loop.pendingRefresh, isTrue);
      expect(loop.pendingBypassRateLimit, isFalse);

      loop.queuePending(bypassRateLimit: true);
      expect(loop.pendingRefresh, isTrue);
      expect(loop.pendingBypassRateLimit, isTrue);
    });

    test('consumePending returns and clears pending flags', () {
      final loop = RefreshLoopState(
        pendingRefresh: true,
        pendingBypassRateLimit: true,
      );

      final consumed = loop.consumePending();
      expect(consumed.hadPending, isTrue);
      expect(consumed.bypassRateLimit, isTrue);
      expect(loop.pendingRefresh, isFalse);
      expect(loop.pendingBypassRateLimit, isFalse);
    });

    test('cancelTimer and reset clear active timer state', () {
      final loop = RefreshLoopState();

      loop.timer = Timer(const Duration(seconds: 1), () {});
      expect(loop.hasTimer, isTrue);
      loop.cancelTimer();
      expect(loop.hasTimer, isFalse);

      loop.timer = Timer(const Duration(seconds: 1), () {});
      loop.pendingRefresh = true;
      loop.pendingBypassRateLimit = true;
      loop.reset();
      expect(loop.hasTimer, isFalse);
      expect(loop.pendingRefresh, isFalse);
      expect(loop.pendingBypassRateLimit, isFalse);
    });
  });

  group('RefreshLoopController', () {
    test('requestRefresh queues pending work while a fetch is in flight', () {
      final controller = RefreshLoopController();
      var queued = false;

      controller.requestRefresh(
        isActive: true,
        isInFlight: true,
        immediate: true,
        bypassRateLimit: true,
        reconcile: () => fail('should not reconcile'),
        runNow: ({required bypassRateLimit}) {
          fail('should not run immediately while in flight');
        },
        scheduleNextTick: () => fail('should not schedule next tick'),
        onQueuePending: () {
          queued = true;
        },
      );

      expect(queued, isTrue);
      expect(controller.hasPendingRefresh, isTrue);
      final pending = controller.consumePending();
      expect(pending.hadPending, isTrue);
      expect(pending.bypassRateLimit, isTrue);
    });

    test('drainPendingRefresh runs queued work and clears pending state', () {
      final controller = RefreshLoopController();
      var drainedBypass = false;
      controller.queuePending(bypassRateLimit: true);

      final drained = controller.drainPendingRefresh(
        isMounted: true,
        isInFlight: false,
        isActive: true,
        runNow: ({required bypassRateLimit}) {
          drainedBypass = bypassRateLimit;
        },
      );

      expect(drained, isTrue);
      expect(drainedBypass, isTrue);
      expect(controller.hasPendingRefresh, isFalse);
    });

    test('scheduleNextTick fires only when still mounted', () {
      fakeAsync((async) {
        final controller = RefreshLoopController();
        var fired = 0;

        controller.scheduleNextTick(
          isActive: () => true,
          reconcile: () => fail('should not reconcile'),
          resolveDelay: () => const Duration(seconds: 5),
          requestRefresh: () {
            fired += 1;
          },
          isMounted: () => true,
        );

        async.elapse(const Duration(seconds: 5));
        expect(fired, 1);

        controller.scheduleNextTick(
          isActive: () => true,
          reconcile: () => fail('should not reconcile'),
          resolveDelay: () => const Duration(seconds: 5),
          requestRefresh: () {
            fired += 1;
          },
          isMounted: () => false,
        );

        async.elapse(const Duration(seconds: 5));
        expect(fired, 1);
      });
    });
  });

  group('RefreshDebouncer', () {
    test('reschedules and fires only the latest callback', () {
      fakeAsync((async) {
        final debouncer = RefreshDebouncer();
        var fired = 0;

        debouncer.schedule(
          delay: const Duration(seconds: 2),
          isMounted: () => true,
          onFire: () {
            fired += 1;
          },
        );
        debouncer.schedule(
          delay: const Duration(seconds: 2),
          isMounted: () => true,
          onFire: () {
            fired += 1;
          },
        );

        async.elapse(const Duration(seconds: 2));
        expect(fired, 1);
      });
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

  group('reconcileSingleLoopRefresh', () {
    test('runs inactive callback when loop is inactive', () {
      final controller = RefreshLoopController();
      var inactiveCalls = 0;
      var refreshCalls = 0;

      final didRequestRefresh = reconcileSingleLoopRefresh(
        loop: controller,
        isActive: false,
        isInFlight: false,
        requestRefresh: () {
          refreshCalls += 1;
        },
        onInactive: () {
          inactiveCalls += 1;
        },
      );

      expect(didRequestRefresh, isFalse);
      expect(inactiveCalls, 1);
      expect(refreshCalls, 0);
    });

    test('requests refresh when active loop needs scheduling', () {
      final controller = RefreshLoopController();
      var refreshCalls = 0;

      final didRequestRefresh = reconcileSingleLoopRefresh(
        loop: controller,
        isActive: true,
        isInFlight: false,
        requestRefresh: () {
          refreshCalls += 1;
        },
        onInactive: () => fail('should not mark active loop as inactive'),
      );

      expect(didRequestRefresh, isTrue);
      expect(refreshCalls, 1);
    });

    test('does not request refresh when active loop already has a timer', () {
      final controller = RefreshLoopController();
      controller.state.timer = Timer(const Duration(seconds: 1), () {});

      final didRequestRefresh = reconcileSingleLoopRefresh(
        loop: controller,
        isActive: true,
        isInFlight: false,
        requestRefresh: () =>
            fail('should not request refresh with active timer'),
        onInactive: () => fail('should not mark active loop as inactive'),
      );

      expect(didRequestRefresh, isFalse);
      controller.state.timer?.cancel();
    });
  });

  group('drainSingleLoopRefreshOrScheduleNext', () {
    test('drains pending refresh before considering schedule/reconcile', () {
      final controller = RefreshLoopController()
        ..queuePending(bypassRateLimit: true);
      var drainedBypass = false;

      final didHandle = drainSingleLoopRefreshOrScheduleNext(
        loop: controller,
        isMounted: true,
        isInFlight: false,
        isActive: true,
        runNow: ({required bypassRateLimit}) {
          drainedBypass = bypassRateLimit;
        },
        scheduleNextTick: () => fail('should not schedule when draining'),
        reconcile: () => fail('should not reconcile when draining'),
      );

      expect(didHandle, isTrue);
      expect(drainedBypass, isTrue);
    });

    test('schedules next tick when nothing is pending and loop is active', () {
      final controller = RefreshLoopController();
      var scheduleNextCalls = 0;

      final didHandle = drainSingleLoopRefreshOrScheduleNext(
        loop: controller,
        isMounted: true,
        isInFlight: false,
        isActive: true,
        runNow: ({required bypassRateLimit}) =>
            fail('should not drain without pending work'),
        scheduleNextTick: () {
          scheduleNextCalls += 1;
        },
        reconcile: () =>
            fail('should not reconcile when tick can be scheduled'),
      );

      expect(didHandle, isTrue);
      expect(scheduleNextCalls, 1);
    });

    test('reconciles when nothing is pending and next tick is not needed', () {
      final controller = RefreshLoopController();
      controller.state.timer = Timer(const Duration(seconds: 1), () {});
      var reconcileCalls = 0;

      final didHandle = drainSingleLoopRefreshOrScheduleNext(
        loop: controller,
        isMounted: true,
        isInFlight: false,
        isActive: true,
        runNow: ({required bypassRateLimit}) {
          fail('should not drain without pending work');
        },
        scheduleNextTick: () => fail('should not schedule with active timer'),
        reconcile: () {
          reconcileCalls += 1;
        },
      );

      expect(didHandle, isFalse);
      expect(reconcileCalls, 1);
      controller.state.timer?.cancel();
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
