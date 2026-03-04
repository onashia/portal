// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'group_monitor_provider.dart';

extension GroupMonitorLoopsExtension on GroupMonitorNotifier {
  bool _baselineActive() {
    return isLoopActive(
      isEnabled: state.isMonitoring,
      sessionEligible: _canPollForCurrentSession(),
      selectionActive: isSelectionActive(state.selectedGroupIds),
    );
  }

  bool _boostActive() {
    return state.isMonitoring &&
        state.isBoostActive &&
        state.boostedGroupId != null &&
        _canPollForCurrentSession();
  }

  void _recordBaselineAttempt([DateTime? at]) {
    state = state.copyWith(
      lastBaselineAttemptAt: at ?? DateTime.now(),
      lastBaselineSkipReason: null,
    );
  }

  void _recordBaselineSkip(String reason, [DateTime? at]) {
    state = state.copyWith(
      lastBaselineAttemptAt: at ?? DateTime.now(),
      lastBaselineSkipReason: reason,
    );
  }

  void _recordBaselineSuccess({
    required int polledGroupCount,
    required int totalInstances,
    DateTime? at,
  }) {
    final timestamp = at ?? DateTime.now();
    state = state.copyWith(
      lastBaselineSuccessAt: timestamp,
      lastBaselinePolledGroupCount: polledGroupCount,
      lastBaselineTotalInstances: totalInstances,
      lastBaselineSkipReason: null,
    );
  }

  void _scheduleSelectionTriggeredBaselineRefresh() {
    _selectionRefreshDebounceTimer?.cancel();
    _baselineLoop.pendingRefresh = true;
    _baselineLoop.pendingBypassRateLimit = false;
    _selectionRefreshDebounceTimer = Timer(
      AppConstants.selectionRefreshDebounceDuration,
      () {
        if (!ref.mounted) {
          return;
        }
        _selectionRefreshDebounceTimer = null;
        _baselineLoop.clearPending();
        _requestBaselineRefresh(immediate: true);
      },
    );
  }

  void _reconcileMonitoringForSelectionState() {
    if (state.selectedGroupIds.isEmpty) {
      if (state.isMonitoring) {
        stopMonitoring();
      }
      _reconcileBaselineLoop();
      _reconcileBoostLoop();
      _reconcileRelayConnection();
      return;
    }

    if (state.selectedGroupIds.isNotEmpty &&
        !state.isMonitoring &&
        _canPollForCurrentSession()) {
      startMonitoring();
    } else if (state.selectedGroupIds.isNotEmpty &&
        !state.isMonitoring &&
        !_canPollForCurrentSession()) {
      AppLogger.debug(
        'Selected groups changed but session is ineligible for monitoring',
        subCategory: 'group_monitor',
      );
    }

    _reconcileBaselineLoop();
    _reconcileBoostLoop();
    _reconcileRelayConnection();
  }

  void _reconcileBaselineLoop() {
    if (!state.isMonitoring) {
      _baselineLoop.reset();
      return;
    }

    if (state.selectedGroupIds.isEmpty) {
      stopMonitoring();
      return;
    }

    if (!_canPollForCurrentSession()) {
      AppLogger.debug(
        'Monitoring active but session is ineligible; stopping monitoring',
        subCategory: 'group_monitor',
      );
      stopMonitoring();
      return;
    }

    if (shouldScheduleNextTick(
      isActive: true,
      hasTimer: _baselineLoop.hasTimer,
      isInFlight: _isAnyFetchInFlight,
      hasPendingRefresh: _baselineLoop.pendingRefresh,
    )) {
      AppLogger.debug(
        'Baseline polling timer missing while monitoring is active; rescheduling',
        subCategory: 'group_monitor',
      );
      _requestBaselineRefresh(immediate: true);
    }
  }

  void _reconcileBoostLoop() {
    if (!_boostActive()) {
      _boostLoop.reset();
      return;
    }

    if (shouldScheduleNextTick(
      isActive: true,
      hasTimer: _boostLoop.hasTimer,
      isInFlight: _isAnyFetchInFlight,
      hasPendingRefresh: _boostLoop.pendingRefresh,
    )) {
      _requestBoostRefresh(immediate: true);
    }
  }

  int _nextPollDelaySeconds() => TimingUtils.secondsWithJitter(
    baseSeconds: AppConstants.pollingIntervalSeconds,
    jitterSeconds: AppConstants.pollingJitterSeconds,
  );

  int _nextBoostPollDelaySeconds() => TimingUtils.secondsWithJitter(
    baseSeconds: AppConstants.boostPollingIntervalSeconds,
    jitterSeconds: AppConstants.boostPollingJitterSeconds,
  );

  void _scheduleNextTick({
    required RefreshLoopState loop,
    required bool Function() isActive,
    required void Function() reconcile,
    required int Function() calculateDelaySeconds,
    required void Function() requestRefresh,
    Duration? overrideDelay,
  }) {
    loop.cancelTimer();

    if (!isActive()) {
      reconcile();
      return;
    }

    final delay = overrideDelay ?? Duration(seconds: calculateDelaySeconds());
    loop.timer = Timer(delay, () {
      if (!ref.mounted) {
        return;
      }
      requestRefresh();
    });
  }

  void _scheduleNextBaselineTick({Duration? overrideDelay}) {
    _scheduleNextTick(
      loop: _baselineLoop,
      isActive: _baselineActive,
      reconcile: _reconcileBaselineLoop,
      calculateDelaySeconds: _nextPollDelaySeconds,
      requestRefresh: () => _requestBaselineRefresh(immediate: true),
      overrideDelay: overrideDelay,
    );
  }

  void _scheduleNextBoostTick({Duration? overrideDelay}) {
    _scheduleNextTick(
      loop: _boostLoop,
      isActive: _boostActive,
      reconcile: _reconcileBoostLoop,
      calculateDelaySeconds: _nextBoostPollDelaySeconds,
      requestRefresh: () => _requestBoostRefresh(immediate: true),
      overrideDelay: overrideDelay,
    );
  }

  void _requestBaselineRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    _requestLoopRefresh(
      loop: _baselineLoop,
      isActive: _baselineActive(),
      reconcile: _reconcileBaselineLoop,
      fetch: fetchGroupInstances,
      scheduleNextTick: () => _scheduleNextBaselineTick(),
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
      onQueuePending: () => _recordBaselineSkip('in_flight_queue'),
    );
  }

  void _requestBoostRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    _requestLoopRefresh(
      loop: _boostLoop,
      isActive: _boostActive(),
      reconcile: _reconcileBoostLoop,
      fetch: fetchBoostedGroupInstances,
      scheduleNextTick: () => _scheduleNextBoostTick(),
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
    );
  }

  void _requestLoopRefresh({
    required RefreshLoopState loop,
    required bool isActive,
    required void Function() reconcile,
    required Future<void> Function({bool bypassRateLimit}) fetch,
    required void Function() scheduleNextTick,
    bool immediate = true,
    bool bypassRateLimit = false,
    void Function()? onQueuePending,
  }) {
    final dispatch = shouldRequestImmediateRefresh(
      isActive: isActive,
      isInFlight: _isAnyFetchInFlight,
      immediate: immediate,
    );
    if (dispatch.shouldReconcile) {
      reconcile();
      return;
    }

    loop.cancelTimer();

    if (dispatch.shouldQueuePending) {
      loop.queuePending(bypassRateLimit: bypassRateLimit);
      onQueuePending?.call();
      return;
    }

    if (dispatch.shouldRunNow) {
      unawaited(fetch(bypassRateLimit: bypassRateLimit));
      return;
    }

    if (dispatch.shouldScheduleTick) {
      scheduleNextTick();
    }
  }

  void _drainPendingRefreshesOrScheduleTicks() {
    if (!ref.mounted || _isAnyFetchInFlight) {
      return;
    }

    final baselineActive = _baselineActive();
    if (shouldDrainPendingRefresh(
      isMounted: ref.mounted,
      isInFlight: _isAnyFetchInFlight,
      hasPendingRefresh: _baselineLoop.pendingRefresh,
      isActive: baselineActive,
    )) {
      final pending = _baselineLoop.consumePending();
      unawaited(fetchGroupInstances(bypassRateLimit: pending.bypassRateLimit));
      return;
    }

    final boostActive = _boostActive();
    if (shouldDrainPendingRefresh(
      isMounted: ref.mounted,
      isInFlight: _isAnyFetchInFlight,
      hasPendingRefresh: _boostLoop.pendingRefresh,
      isActive: boostActive,
    )) {
      final pending = _boostLoop.consumePending();
      unawaited(
        fetchBoostedGroupInstances(bypassRateLimit: pending.bypassRateLimit),
      );
      return;
    }

    if (shouldScheduleNextTick(
      isActive: baselineActive,
      hasTimer: _baselineLoop.hasTimer,
      isInFlight: _isAnyFetchInFlight,
      hasPendingRefresh: _baselineLoop.pendingRefresh,
    )) {
      _scheduleNextBaselineTick();
    } else if (!baselineActive) {
      _baselineLoop.reset();
    }

    if (shouldScheduleNextTick(
      isActive: boostActive,
      hasTimer: _boostLoop.hasTimer,
      isInFlight: _isAnyFetchInFlight,
      hasPendingRefresh: _boostLoop.pendingRefresh,
    )) {
      _scheduleNextBoostTick();
    } else if (!boostActive) {
      _boostLoop.reset();
    }
  }

  /// Requests a baseline monitoring refresh through the queued single-flight
  /// lifecycle so manual refreshes and automatic triggers share the same flow.
  ///
  /// When [immediate] is true, this starts a refresh now (or marks one as
  /// pending if another fetch is already in-flight). When false, it schedules
  /// the next baseline tick using the normal polling cadence.
  void _requestRefreshInternal({bool immediate = true}) {
    _selectionRefreshDebounceTimer?.cancel();
    _selectionRefreshDebounceTimer = null;
    _baselineLoop.clearPending();
    _requestBaselineRefresh(immediate: immediate, bypassRateLimit: true);
  }

  void _startMonitoringInternal() {
    AppLogger.info('Starting monitoring', subCategory: 'group_monitor');

    if (!_canPollForCurrentSession()) {
      AppLogger.warning(
        'Cannot start monitoring without an active matching session',
        subCategory: 'group_monitor',
      );
      return;
    }

    if (state.selectedGroupIds.isEmpty) {
      AppLogger.warning(
        'Cannot start monitoring with no selected groups',
        subCategory: 'group_monitor',
      );
      return;
    }

    if (state.isMonitoring) {
      AppLogger.warning(
        'Already monitoring, skipping start',
        subCategory: 'group_monitor',
      );
      return;
    }

    _hasBaseline = false;
    state = state.copyWith(isMonitoring: true);
    AppLogger.info(
      'Started monitoring ${state.selectedGroupIds.length} groups',
      subCategory: 'group_monitor',
    );

    _requestBaselineRefresh(immediate: true);
    _reconcileBoostLoop();
    _reconcileBaselineLoop();
    _reconcileRelayConnection();
  }

  void _stopMonitoringInternal() {
    if (!state.isMonitoring) {
      return;
    }

    _baselineLoop.reset();
    _boostLoop.reset();
    _selectionRefreshDebounceTimer?.cancel();
    _selectionRefreshDebounceTimer = null;
    unawaited(
      _clearBoost(
        persist: true,
        logExpired: false,
        requestBaselineRecovery: false,
      ),
    );
    state = state.copyWith(isMonitoring: false);
    _backoffDelay = 1;
    _reconcileRelayConnection();

    AppLogger.info('Stopped monitoring', subCategory: 'group_monitor');
  }
}
