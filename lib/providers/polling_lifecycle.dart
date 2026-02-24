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
