import 'dart:async';

typedef RefreshRequestDecision = ({bool shouldQueuePending, bool shouldRunNow});
typedef PendingRefreshState = ({
  bool pendingRefresh,
  bool pendingBypassRateLimit,
});
typedef RefreshDispatchDecision = ({
  bool shouldReconcile,
  bool shouldQueuePending,
  bool shouldRunNow,
  bool shouldScheduleTick,
});
typedef LoopRefreshRunner = void Function({required bool bypassRateLimit});

bool isSessionEligible({
  required bool isAuthenticated,
  required String? authenticatedUserId,
  required String expectedUserId,
}) {
  return isAuthenticated && authenticatedUserId == expectedUserId;
}

bool isSelectionActive(Set<String> selectedGroupIds) {
  return selectedGroupIds.isNotEmpty;
}

bool isLoopActive({
  required bool isEnabled,
  required bool sessionEligible,
  required bool selectionActive,
}) {
  return isEnabled && sessionEligible && selectionActive;
}

bool becameActive(bool previousActive, bool nextActive) {
  return !previousActive && nextActive;
}

bool becameInactive(bool previousActive, bool nextActive) {
  return previousActive && !nextActive;
}

RefreshRequestDecision resolveRefreshRequestDecision({
  required bool isInFlight,
}) {
  return (shouldQueuePending: isInFlight, shouldRunNow: !isInFlight);
}

/// Merges an incoming refresh request into the pending state.
///
/// The bypass flag is sticky: once any queued request has requested a bypass,
/// the merged pending state retains bypass even if the new request does not.
PendingRefreshState mergePendingRefreshState({
  required bool currentPendingBypassRateLimit,
  required bool nextBypassRateLimit,
}) {
  return (
    pendingRefresh: true,
    pendingBypassRateLimit:
        currentPendingBypassRateLimit || nextBypassRateLimit,
  );
}

class RefreshLoopState {
  Timer? timer;
  bool pendingRefresh;
  bool pendingBypassRateLimit;

  RefreshLoopState({
    this.timer,
    this.pendingRefresh = false,
    this.pendingBypassRateLimit = false,
  });

  bool get hasTimer => timer != null;

  void cancelTimer() {
    timer?.cancel();
    timer = null;
  }

  void clearPending() {
    pendingRefresh = false;
    pendingBypassRateLimit = false;
  }

  void reset() {
    cancelTimer();
    clearPending();
  }

  void queuePending({required bool bypassRateLimit}) {
    final merged = mergePendingRefreshState(
      currentPendingBypassRateLimit: pendingBypassRateLimit,
      nextBypassRateLimit: bypassRateLimit,
    );
    pendingRefresh = merged.pendingRefresh;
    pendingBypassRateLimit = merged.pendingBypassRateLimit;
  }

  ({bool hadPending, bool bypassRateLimit}) consumePending() {
    final hadPending = pendingRefresh;
    final bypassRateLimit = pendingBypassRateLimit;
    clearPending();
    return (hadPending: hadPending, bypassRateLimit: bypassRateLimit);
  }
}

class RefreshLoopController {
  RefreshLoopController({RefreshLoopState? state})
    : state = state ?? RefreshLoopState();

  final RefreshLoopState state;

  bool get hasTimer => state.hasTimer;
  bool get hasPendingRefresh => state.pendingRefresh;

  void cancelTimer() {
    state.cancelTimer();
  }

  void clearPending() {
    state.clearPending();
  }

  void reset() {
    state.reset();
  }

  void queuePending({required bool bypassRateLimit}) {
    state.queuePending(bypassRateLimit: bypassRateLimit);
  }

  ({bool hadPending, bool bypassRateLimit}) consumePending() {
    return state.consumePending();
  }

  void requestRefresh({
    required bool isActive,
    required bool isInFlight,
    required bool immediate,
    required bool bypassRateLimit,
    required void Function() reconcile,
    required LoopRefreshRunner runNow,
    required void Function() scheduleNextTick,
    void Function()? onQueuePending,
  }) {
    final dispatch = shouldRequestImmediateRefresh(
      isActive: isActive,
      isInFlight: isInFlight,
      immediate: immediate,
    );
    if (dispatch.shouldReconcile) {
      reconcile();
      return;
    }

    cancelTimer();

    if (dispatch.shouldQueuePending) {
      queuePending(bypassRateLimit: bypassRateLimit);
      onQueuePending?.call();
      return;
    }

    if (dispatch.shouldRunNow) {
      runNow(bypassRateLimit: bypassRateLimit);
      return;
    }

    if (dispatch.shouldScheduleTick) {
      scheduleNextTick();
    }
  }

  bool drainPendingRefresh({
    required bool isMounted,
    required bool isInFlight,
    required bool isActive,
    required LoopRefreshRunner runNow,
  }) {
    if (!shouldDrainPendingRefresh(
      isMounted: isMounted,
      isInFlight: isInFlight,
      hasPendingRefresh: hasPendingRefresh,
      isActive: isActive,
    )) {
      return false;
    }

    final pending = consumePending();
    runNow(bypassRateLimit: pending.bypassRateLimit);
    return true;
  }

  bool shouldScheduleNext({required bool isActive, required bool isInFlight}) {
    return shouldScheduleNextTick(
      isActive: isActive,
      hasTimer: hasTimer,
      isInFlight: isInFlight,
      hasPendingRefresh: hasPendingRefresh,
    );
  }

  void scheduleNextTick({
    required bool Function() isActive,
    required void Function() reconcile,
    required Duration Function() resolveDelay,
    required void Function() requestRefresh,
    required bool Function() isMounted,
    Duration? overrideDelay,
  }) {
    cancelTimer();

    if (!isActive()) {
      reconcile();
      return;
    }

    final delay = overrideDelay ?? resolveDelay();
    state.timer = Timer(delay, () {
      if (!isMounted()) {
        return;
      }
      requestRefresh();
    });
  }
}

class RefreshDebouncer {
  Timer? _timer;

  bool get isScheduled => _timer != null;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void schedule({
    required Duration delay,
    required bool Function() isMounted,
    required void Function() onFire,
  }) {
    cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (!isMounted()) {
        return;
      }
      onFire();
    });
  }
}

/// Decides how to handle an incoming refresh request.
///
/// Dispatch table:
/// - inactive                 → reconcile loop (fix invariants, don't fetch)
/// - active + in-flight       → queue pending (drain after current fetch)
/// - active + not in-flight + immediate → run now
/// - active + not in-flight + not immediate → schedule next tick
RefreshDispatchDecision shouldRequestImmediateRefresh({
  required bool isActive,
  required bool isInFlight,
  required bool immediate,
}) {
  if (!isActive) {
    return (
      shouldReconcile: true,
      shouldQueuePending: false,
      shouldRunNow: false,
      shouldScheduleTick: false,
    );
  }

  final decision = resolveRefreshRequestDecision(isInFlight: isInFlight);
  if (decision.shouldQueuePending) {
    return (
      shouldReconcile: false,
      shouldQueuePending: true,
      shouldRunNow: false,
      shouldScheduleTick: false,
    );
  }

  if (immediate) {
    return (
      shouldReconcile: false,
      shouldQueuePending: false,
      shouldRunNow: true,
      shouldScheduleTick: false,
    );
  }

  return (
    shouldReconcile: false,
    shouldQueuePending: false,
    shouldRunNow: false,
    shouldScheduleTick: true,
  );
}

bool shouldScheduleNextTick({
  required bool isActive,
  required bool hasTimer,
  required bool isInFlight,
  required bool hasPendingRefresh,
}) {
  return isActive && !hasTimer && !isInFlight && !hasPendingRefresh;
}

bool shouldDrainPendingRefresh({
  required bool isMounted,
  required bool isInFlight,
  required bool hasPendingRefresh,
  required bool isActive,
}) {
  return isMounted && !isInFlight && hasPendingRefresh && isActive;
}

/// Returns how long to wait before the next fetch attempt given an active
/// rate-limit cooldown.
///
/// [safetyBuffer] is added on top of [remainingCooldown] so the cooldown has
/// definitively expired server-side before the next request fires. When the
/// cooldown has already elapsed (≤ zero), the buffer alone is returned as a
/// minimal nudge rather than firing immediately.
Duration resolveCooldownAwareDelay({
  required Duration? remainingCooldown,
  required Duration fallbackDelay,
  Duration safetyBuffer = const Duration(milliseconds: 250),
}) {
  if (remainingCooldown == null) {
    return fallbackDelay;
  }

  if (remainingCooldown <= Duration.zero) {
    return safetyBuffer;
  }

  return remainingCooldown + safetyBuffer;
}
