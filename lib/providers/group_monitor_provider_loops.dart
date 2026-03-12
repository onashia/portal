// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
// This part-file's controller coordinates GroupMonitorNotifier internals within
// the same library and intentionally reads/writes Riverpod's protected members.

part of 'group_monitor_provider.dart';

class _GroupMonitorLoopController {
  _GroupMonitorLoopController(this.notifier);

  final GroupMonitorNotifier notifier;

  bool baselineActive() {
    final state = notifier.state;
    return isLoopActive(
      isEnabled: state.isMonitoring,
      sessionEligible: notifier._canPollForCurrentSession(),
      selectionActive: isSelectionActive(state.selectedGroupIds),
    );
  }

  bool boostActive() {
    final state = notifier.state;
    return state.isMonitoring &&
        state.isBoostActive &&
        state.boostedGroupId != null &&
        notifier._canPollForCurrentSession();
  }

  void recordBaselineAttempt([DateTime? at]) {
    notifier.state = notifier.state.copyWith(
      lastBaselineAttemptAt: at ?? DateTime.now(),
      lastBaselineSkipReason: null,
    );
  }

  void recordBaselineSkip(String reason, [DateTime? at]) {
    notifier.state = notifier.state.copyWith(
      lastBaselineAttemptAt: at ?? DateTime.now(),
      lastBaselineSkipReason: reason,
    );
  }

  void recordBaselineSuccess({
    required int polledGroupCount,
    required int totalInstances,
    DateTime? at,
  }) {
    final timestamp = at ?? DateTime.now();
    notifier.state = notifier.state.copyWith(
      lastBaselineSuccessAt: timestamp,
      lastBaselinePolledGroupCount: polledGroupCount,
      lastBaselineTotalInstances: totalInstances,
      lastBaselineSkipReason: null,
    );
  }

  void cancelSelectionRefreshDebounce() {
    notifier._selectionRefreshDebouncer.cancel();
  }

  void scheduleSelectionTriggeredBaselineRefresh() {
    notifier._selectionRefreshDebouncer.cancel();
    notifier._baselineLoop.queuePending(bypassRateLimit: false);
    notifier._selectionRefreshDebouncer.schedule(
      delay: AppConstants.selectionRefreshDebounceDuration,
      isMounted: () => notifier.ref.mounted,
      onFire: () {
        notifier._baselineLoop.clearPending();
        requestBaselineRefresh(immediate: true);
      },
    );
  }

  void reconcileMonitoringForSelectionState() {
    final state = notifier.state;
    if (state.selectedGroupIds.isEmpty) {
      if (state.isMonitoring) {
        stopMonitoring();
      }
      reconcileBaselineLoop();
      reconcileBoostLoop();
      notifier._relayController.reconcileConnection();
      return;
    }

    if (!state.isMonitoring && notifier._canPollForCurrentSession()) {
      startMonitoring();
    } else if (!state.isMonitoring && !notifier._canPollForCurrentSession()) {
      AppLogger.debug(
        'Selected groups changed but session is ineligible for monitoring',
        subCategory: 'group_monitor',
      );
    }

    reconcileBaselineLoop();
    reconcileBoostLoop();
    notifier._relayController.reconcileConnection();
  }

  void reconcileBaselineLoop() {
    final state = notifier.state;
    if (!state.isMonitoring) {
      notifier._baselineLoop.reset();
      return;
    }

    if (state.selectedGroupIds.isEmpty) {
      stopMonitoring();
      return;
    }

    if (!notifier._canPollForCurrentSession()) {
      AppLogger.debug(
        'Monitoring active but session is ineligible; stopping monitoring',
        subCategory: 'group_monitor',
      );
      stopMonitoring();
      return;
    }

    if (notifier._baselineLoop.shouldScheduleNext(
      isActive: true,
      isInFlight: notifier._isAnyFetchInFlight,
    )) {
      AppLogger.debug(
        'Baseline polling timer missing while monitoring is active; rescheduling',
        subCategory: 'group_monitor',
      );
      requestBaselineRefresh(immediate: true);
    }
  }

  void reconcileBoostLoop() {
    final state = notifier.state;
    if (state.isBoostActive &&
        state.boostExpiresAt != null &&
        !state.boostExpiresAt!.isAfter(DateTime.now())) {
      unawaited(
        notifier._persistenceController.clearBoost(
          persist: true,
          logExpired: true,
        ),
      );
      return;
    }

    if (!boostActive()) {
      notifier._boostLoop.reset();
      return;
    }

    if (notifier._boostLoop.shouldScheduleNext(
      isActive: true,
      isInFlight: notifier._isAnyFetchInFlight,
    )) {
      requestBoostRefresh(immediate: true);
    }
  }

  Duration nextPollDelay() {
    return Duration(
      seconds: TimingUtils.secondsWithJitter(
        baseSeconds: AppConstants.pollingIntervalSeconds,
        jitterSeconds: AppConstants.pollingJitterSeconds,
      ),
    );
  }

  Duration nextBoostPollDelay() {
    return Duration(
      seconds: TimingUtils.secondsWithJitter(
        baseSeconds: AppConstants.boostPollingIntervalSeconds,
        jitterSeconds: AppConstants.boostPollingJitterSeconds,
      ),
    );
  }

  void scheduleNextTick({
    required RefreshLoopController loop,
    required bool Function() isActive,
    required void Function() reconcile,
    required Duration Function() resolveDelay,
    required void Function() requestRefresh,
    Duration? overrideDelay,
  }) {
    loop.scheduleNextTick(
      isActive: isActive,
      reconcile: reconcile,
      resolveDelay: resolveDelay,
      requestRefresh: requestRefresh,
      isMounted: () => notifier.ref.mounted,
      overrideDelay: overrideDelay,
    );
  }

  void scheduleNextBaselineTick({Duration? overrideDelay}) {
    scheduleNextTick(
      loop: notifier._baselineLoop,
      isActive: baselineActive,
      reconcile: reconcileBaselineLoop,
      resolveDelay: nextPollDelay,
      requestRefresh: () => requestBaselineRefresh(immediate: true),
      overrideDelay: overrideDelay,
    );
  }

  void scheduleNextBoostTick({Duration? overrideDelay}) {
    scheduleNextTick(
      loop: notifier._boostLoop,
      isActive: boostActive,
      reconcile: reconcileBoostLoop,
      resolveDelay: nextBoostPollDelay,
      requestRefresh: () => requestBoostRefresh(immediate: true),
      overrideDelay: overrideDelay,
    );
  }

  void requestBaselineRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    requestLoopRefresh(
      loop: notifier._baselineLoop,
      isActive: baselineActive(),
      reconcile: reconcileBaselineLoop,
      fetch: notifier.fetchGroupInstances,
      scheduleNextTick: () => scheduleNextBaselineTick(),
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
      onQueuePending: () => recordBaselineSkip('in_flight_queue'),
    );
  }

  void requestBoostRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    requestLoopRefresh(
      loop: notifier._boostLoop,
      isActive: boostActive(),
      reconcile: reconcileBoostLoop,
      fetch: notifier.fetchBoostedGroupInstances,
      scheduleNextTick: () => scheduleNextBoostTick(),
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
    );
  }

  void requestLoopRefresh({
    required RefreshLoopController loop,
    required bool isActive,
    required void Function() reconcile,
    required Future<void> Function({bool bypassRateLimit}) fetch,
    required void Function() scheduleNextTick,
    bool immediate = true,
    bool bypassRateLimit = false,
    void Function()? onQueuePending,
  }) {
    loop.requestRefresh(
      isActive: isActive,
      isInFlight: notifier._isAnyFetchInFlight,
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
      reconcile: reconcile,
      runNow: ({required bypassRateLimit}) {
        unawaited(fetch(bypassRateLimit: bypassRateLimit));
      },
      scheduleNextTick: scheduleNextTick,
      onQueuePending: onQueuePending,
    );
  }

  void drainPendingRefreshesOrScheduleTicks() {
    if (!notifier.ref.mounted || notifier._isAnyFetchInFlight) {
      return;
    }

    final baselineActiveNow = baselineActive();
    if (notifier._baselineLoop.drainPendingRefresh(
      isMounted: notifier.ref.mounted,
      isInFlight: notifier._isAnyFetchInFlight,
      isActive: baselineActiveNow,
      runNow: ({required bypassRateLimit}) {
        unawaited(
          notifier.fetchGroupInstances(bypassRateLimit: bypassRateLimit),
        );
      },
    )) {
      return;
    }

    final boostActiveNow = boostActive();
    if (notifier._boostLoop.drainPendingRefresh(
      isMounted: notifier.ref.mounted,
      isInFlight: notifier._isAnyFetchInFlight,
      isActive: boostActiveNow,
      runNow: ({required bypassRateLimit}) {
        unawaited(
          notifier.fetchBoostedGroupInstances(bypassRateLimit: bypassRateLimit),
        );
      },
    )) {
      return;
    }

    if (notifier._baselineLoop.shouldScheduleNext(
      isActive: baselineActiveNow,
      isInFlight: notifier._isAnyFetchInFlight,
    )) {
      scheduleNextBaselineTick();
    } else if (!baselineActiveNow) {
      notifier._baselineLoop.reset();
    }

    if (notifier._boostLoop.shouldScheduleNext(
      isActive: boostActiveNow,
      isInFlight: notifier._isAnyFetchInFlight,
    )) {
      scheduleNextBoostTick();
    } else if (!boostActiveNow) {
      notifier._boostLoop.reset();
    }
  }

  void requestRefresh({bool immediate = true}) {
    notifier._selectionRefreshDebouncer.cancel();
    notifier._baselineLoop.clearPending();
    requestBaselineRefresh(immediate: immediate, bypassRateLimit: true);
  }

  void startMonitoring() {
    AppLogger.info('Starting monitoring', subCategory: 'group_monitor');

    if (!notifier._canPollForCurrentSession()) {
      AppLogger.warning(
        'Cannot start monitoring without an active matching session',
        subCategory: 'group_monitor',
      );
      return;
    }

    if (notifier.state.selectedGroupIds.isEmpty) {
      AppLogger.warning(
        'Cannot start monitoring with no selected groups',
        subCategory: 'group_monitor',
      );
      return;
    }

    if (notifier.state.isMonitoring) {
      AppLogger.warning(
        'Already monitoring, skipping start',
        subCategory: 'group_monitor',
      );
      return;
    }

    notifier._hasBaseline = false;
    notifier.state = notifier.state.copyWith(isMonitoring: true);
    AppLogger.info(
      'Started monitoring ${notifier.state.selectedGroupIds.length} groups',
      subCategory: 'group_monitor',
    );

    requestBaselineRefresh(immediate: true);
    reconcileBoostLoop();
    reconcileBaselineLoop();
    notifier._relayController.reconcileConnection();
  }

  void stopMonitoring() {
    if (!notifier.state.isMonitoring) {
      return;
    }

    notifier._baselineLoop.reset();
    notifier._boostLoop.reset();
    notifier._selectionRefreshDebouncer.cancel();
    unawaited(
      notifier._persistenceController.clearBoost(
        persist: true,
        logExpired: false,
        requestBaselineRecovery: false,
      ),
    );
    notifier.state = notifier.state.copyWith(isMonitoring: false);
    notifier._backoffDelay = 1;
    notifier._relayController.reconcileConnection();

    AppLogger.info('Stopped monitoring', subCategory: 'group_monitor');
  }
}
