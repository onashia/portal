part of 'group_monitor_provider.dart';

class _GroupMonitorLoopController {
  _GroupMonitorLoopController(this.notifier);

  final GroupMonitorNotifier notifier;

  bool baselineActive() {
    final state = notifier._currentState;
    return isLoopActive(
      isEnabled: state.isMonitoring,
      sessionEligible: notifier._canPollForCurrentSession(),
      selectionActive: isSelectionActive(state.selectedGroupIds),
    );
  }

  bool boostActive() {
    final state = notifier._currentState;
    return state.isMonitoring &&
        state.isBoostActive &&
        state.boostedGroupId != null &&
        notifier._canPollForCurrentSession();
  }

  void recordBaselineAttempt([DateTime? at]) {
    notifier._replaceState(
      notifier._currentState.copyWith(
        lastBaselineAttemptAt: at ?? DateTime.now(),
        lastBaselineSkipReason: null,
      ),
    );
  }

  void recordBaselineSkip(String reason, [DateTime? at]) {
    notifier._replaceState(
      notifier._currentState.copyWith(
        lastBaselineAttemptAt: at ?? DateTime.now(),
        lastBaselineSkipReason: reason,
      ),
    );
  }

  void recordBaselineSuccess({
    required int polledGroupCount,
    required int totalInstances,
    DateTime? at,
  }) {
    final timestamp = at ?? DateTime.now();
    notifier._replaceState(
      notifier._currentState.copyWith(
        lastBaselineSuccessAt: timestamp,
        lastBaselinePolledGroupCount: polledGroupCount,
        lastBaselineTotalInstances: totalInstances,
        lastBaselineSkipReason: null,
      ),
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
      isMounted: () => notifier._mounted,
      onFire: () {
        notifier._baselineLoop.clearPending();
        requestBaselineRefresh(immediate: true);
      },
    );
  }

  void reconcileMonitoringForSelectionState() {
    final state = notifier._currentState;
    if (state.selectedGroupIds.isEmpty) {
      if (state.isMonitoring) {
        stopMonitoring();
      }
      reconcileBaselineLoop();
      reconcileBoostLoop();
      notifier._reconcileRelayConnection();
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
    notifier._reconcileRelayConnection();
  }

  void reconcileBaselineLoop() {
    final state = notifier._currentState;
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
    final state = notifier._currentState;
    if (state.isBoostActive &&
        state.boostExpiresAt != null &&
        !state.boostExpiresAt!.isAfter(DateTime.now())) {
      unawaited(notifier._clearBoost(persist: true, logExpired: true));
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
      isMounted: () => notifier._mounted,
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
    if (!notifier._mounted || notifier._isAnyFetchInFlight) {
      return;
    }

    final baselineActiveNow = baselineActive();
    if (notifier._baselineLoop.drainPendingRefresh(
      isMounted: notifier._mounted,
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
      isMounted: notifier._mounted,
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

    if (notifier._currentState.selectedGroupIds.isEmpty) {
      AppLogger.warning(
        'Cannot start monitoring with no selected groups',
        subCategory: 'group_monitor',
      );
      return;
    }

    if (notifier._currentState.isMonitoring) {
      AppLogger.warning(
        'Already monitoring, skipping start',
        subCategory: 'group_monitor',
      );
      return;
    }

    notifier._hasBaseline = false;
    notifier._replaceState(notifier._currentState.copyWith(isMonitoring: true));
    AppLogger.info(
      'Started monitoring ${notifier._currentState.selectedGroupIds.length} groups',
      subCategory: 'group_monitor',
    );

    requestBaselineRefresh(immediate: true);
    reconcileBoostLoop();
    reconcileBaselineLoop();
    notifier._reconcileRelayConnection();
  }

  void stopMonitoring() {
    if (!notifier._currentState.isMonitoring) {
      return;
    }

    notifier._baselineLoop.reset();
    notifier._boostLoop.reset();
    notifier._selectionRefreshDebouncer.cancel();
    unawaited(
      notifier._clearBoost(
        persist: true,
        logExpired: false,
        requestBaselineRecovery: false,
      ),
    );
    notifier._replaceState(
      notifier._currentState.copyWith(isMonitoring: false),
    );
    notifier._backoffDelay = 1;
    notifier._reconcileRelayConnection();

    AppLogger.info('Stopped monitoring', subCategory: 'group_monitor');
  }
}

extension GroupMonitorLoopsExtension on GroupMonitorNotifier {
  bool _baselineActive() => _loopController.baselineActive();

  bool _boostActive() => _loopController.boostActive();

  void _recordBaselineAttempt([DateTime? at]) =>
      _loopController.recordBaselineAttempt(at);

  void _recordBaselineSkip(String reason, [DateTime? at]) =>
      _loopController.recordBaselineSkip(reason, at);

  void _recordBaselineSuccess({
    required int polledGroupCount,
    required int totalInstances,
    DateTime? at,
  }) {
    _loopController.recordBaselineSuccess(
      polledGroupCount: polledGroupCount,
      totalInstances: totalInstances,
      at: at,
    );
  }

  void _scheduleSelectionTriggeredBaselineRefresh() =>
      _loopController.scheduleSelectionTriggeredBaselineRefresh();

  void _reconcileMonitoringForSelectionState() =>
      _loopController.reconcileMonitoringForSelectionState();

  void _reconcileBaselineLoop() => _loopController.reconcileBaselineLoop();

  void _reconcileBoostLoop() => _loopController.reconcileBoostLoop();

  Duration _nextPollDelay() => _loopController.nextPollDelay();

  Duration _nextBoostPollDelay() => _loopController.nextBoostPollDelay();

  void _scheduleNextBaselineTick({Duration? overrideDelay}) {
    _loopController.scheduleNextBaselineTick(overrideDelay: overrideDelay);
  }

  void _scheduleNextBoostTick({Duration? overrideDelay}) {
    _loopController.scheduleNextBoostTick(overrideDelay: overrideDelay);
  }

  void _requestBaselineRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    _loopController.requestBaselineRefresh(
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
    );
  }

  void _requestBoostRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    _loopController.requestBoostRefresh(
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
    );
  }

  void _drainPendingRefreshesOrScheduleTicks() =>
      _loopController.drainPendingRefreshesOrScheduleTicks();

  void _requestRefreshInternal({bool immediate = true}) =>
      _loopController.requestRefresh(immediate: immediate);

  void _startMonitoringInternal() => _loopController.startMonitoring();

  void _stopMonitoringInternal() => _loopController.stopMonitoring();
}
