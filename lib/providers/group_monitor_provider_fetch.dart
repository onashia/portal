// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'group_monitor_provider.dart';

typedef FetchContext = ({List<String> selectedGroupIds, DateTime attemptAt});

typedef FetchExecutionResult = ({
  dynamic api,
  Map<String, List<GroupInstanceWithGroup>> previousGroupInstances,
  Map<String, String> previousGroupErrors,
  Map<String, List<GroupInstanceWithGroup>> newGroupInstances,
  Map<String, String> newGroupErrors,
  GroupInstanceWithGroup? newestInstance,
  bool didInstancesChange,
  List<({String groupId, dynamic response})> responses,
  bool isMounted,
});

typedef FetchProcessingResult = ({
  List<GroupInstanceWithGroup> newInstances,
  Map<String, List<GroupInstanceWithGroup>> groupInstances,
  GroupInstanceWithGroup? newestInstance,
  bool didInstancesChange,
});

extension GroupMonitorFetchExtension on GroupMonitorNotifier {
  String? _validateFetchPreconditions({
    required DateTime attemptAt,
    required bool bypassRateLimit,
  }) {
    if (!_baselineActive()) {
      AppLogger.debug(
        'Skipping instance fetch for inactive baseline loop',
        subCategory: 'group_monitor',
      );
      _recordBaselineSkip('inactive', attemptAt);
      _reconcileBaselineLoop();
      return 'inactive';
    }

    final decision = resolveRefreshRequestDecision(
      isInFlight: _isAnyFetchInFlight,
    );
    if (decision.shouldQueuePending) {
      _baselineLoop.queuePending(bypassRateLimit: bypassRateLimit);
      AppLogger.debug(
        'Fetch already in progress, queueing pending baseline refresh',
        subCategory: 'group_monitor',
      );
      _recordBaselineSkip('in_flight_queue', attemptAt);
      return 'in_flight_queue';
    }

    return null;
  }

  FetchContext? _prepareFetchContext({
    required DateTime attemptAt,
    required bool bypassRateLimit,
  }) {
    final selectedGroupIdSet = state.selectedGroupIds;
    final selectedGroupIds = selectedGroupIdSet.toList(growable: true);
    if (state.isBoostActive && state.boostedGroupId != null) {
      selectedGroupIds.remove(state.boostedGroupId);
    }
    selectedGroupIds.sort();
    if (selectedGroupIds.isEmpty) {
      AppLogger.debug(
        'No non-boost groups selected, skipping baseline fetch',
        subCategory: 'group_monitor',
      );
      _recordBaselineSkip('no_targets', attemptAt);
      _scheduleNextBaselineTick();
      return null;
    }

    if (RefreshCooldownHandler.shouldDeferForCooldown(
      ref: ref,
      bypassRateLimit: bypassRateLimit,
      lane: ApiRequestLane.groupBaseline,
      logContext: 'group_monitor',
      fallbackDelay: Duration(seconds: _nextPollDelaySeconds()),
      onDefer: (delay) {
        _recordBaselineSkip('cooldown', attemptAt);
        _scheduleNextBaselineTick(overrideDelay: delay);
      },
    )) {
      return null;
    }

    return (selectedGroupIds: selectedGroupIds, attemptAt: attemptAt);
  }

  Future<FetchExecutionResult> _executeChunkedFetch(
    FetchContext context,
  ) async {
    AppLogger.debug(
      'Fetching instances for ${context.selectedGroupIds.length} groups',
      subCategory: 'group_monitor',
    );

    final api = ref.read(vrchatApiProvider);
    final previousGroupInstances = state.groupInstances;
    final previousGroupErrors = state.groupErrors;
    final newGroupInstances = <String, List<GroupInstanceWithGroup>>{};
    final newGroupErrors = <String, String>{};
    GroupInstanceWithGroup? newestInstance;
    final selectedGroupIdSet = state.selectedGroupIds;
    final excludedGroupIds = selectedGroupIdSet.difference(
      context.selectedGroupIds.toSet(),
    );
    for (final excludedGroupId in excludedGroupIds) {
      final previousInstances = previousGroupInstances[excludedGroupId] ?? [];
      newGroupInstances[excludedGroupId] = previousInstances;
      for (final previous in previousInstances) {
        newestInstance = pickNewestInstance(newestInstance, previous);
      }

      final previousError = previousGroupErrors[excludedGroupId];
      if (previousError != null) {
        newGroupErrors[excludedGroupId] = previousError;
      }
    }
    final didInstancesChange = hasGroupInstanceKeyMismatch(
      selectedGroupIds: selectedGroupIdSet,
      groupInstances: previousGroupInstances,
    );

    final responses = await fetchGroupInstancesChunked(
      orderedGroupIds: context.selectedGroupIds,
      maxConcurrentRequests: AppConstants.groupInstancesMaxConcurrentRequests,
      fetchGroupInstances: (groupId) async {
        ref
            .read(apiCallCounterProvider.notifier)
            .incrementApiCall(lane: ApiRequestLane.groupBaseline);
        try {
          return await api.rawApi
              .getUsersApi()
              .getUserGroupInstancesForGroup(
                userId: arg,
                groupId: groupId,
                extra: apiRequestLaneExtra(ApiRequestLane.groupBaseline),
              )
              .timeout(
                const Duration(
                  seconds: AppConstants.groupInstancesRequestTimeoutSeconds,
                ),
              );
        } catch (e, s) {
          AppLogger.error(
            'Failed to fetch instances for group $groupId',
            subCategory: 'group_monitor',
            error: e,
            stackTrace: s,
          );
          return null;
        }
      },
    );
    if (!ref.mounted) {
      return (
        api: api,
        previousGroupInstances: previousGroupInstances,
        previousGroupErrors: previousGroupErrors,
        newGroupInstances: newGroupInstances,
        newGroupErrors: newGroupErrors,
        newestInstance: newestInstance,
        didInstancesChange: didInstancesChange,
        responses: responses,
        isMounted: false,
      );
    }

    return (
      api: api,
      previousGroupInstances: previousGroupInstances,
      previousGroupErrors: previousGroupErrors,
      newGroupInstances: newGroupInstances,
      newGroupErrors: newGroupErrors,
      newestInstance: newestInstance,
      didInstancesChange: didInstancesChange,
      responses: responses,
      isMounted: true,
    );
  }

  Future<FetchProcessingResult> _processFetchResponses(
    FetchExecutionResult executionResult,
    FetchContext context,
  ) async {
    final responses = executionResult.responses;
    final previousGroupInstances = executionResult.previousGroupInstances;
    final newInstances = <GroupInstanceWithGroup>[];
    var newestInstance = executionResult.newestInstance;
    var didInstancesChange = executionResult.didInstancesChange;
    final newGroupInstances = executionResult.newGroupInstances;
    final newGroupErrors = executionResult.newGroupErrors;

    for (final groupResponse in responses) {
      final groupId = groupResponse.groupId;
      final response = groupResponse.response;
      final previousInstances = previousGroupInstances[groupId] ?? [];

      if (response == null) {
        AppLogger.error(
          'Failed to fetch instances for group $groupId',
          subCategory: 'group_monitor',
        );
        newGroupErrors[groupId] = 'Failed to fetch instances';
        newGroupInstances[groupId] = previousInstances;
        for (final previous in previousInstances) {
          newestInstance = pickNewestInstance(newestInstance, previous);
        }
        continue;
      }

      final instances = response.data?.instances ?? [];

      AppLogger.debug(
        'Group returned ${instances.length} instances',
        subCategory: 'group_monitor',
      );

      await _attemptAutoInviteIfNewInstances(
        previousInstances: previousInstances,
        instances: instances,
        groupId: groupId,
        laneLabel: 'group',
      );

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: groupId,
        fetchedInstances: instances,
        previousInstances: previousInstances,
        detectedAt: context.attemptAt,
      );
      newInstances.addAll(merged.newInstances);
      if (merged.didChange) {
        didInstancesChange = true;
      }
      final effectiveInstances = merged.effectiveInstances;
      newGroupInstances[groupId] = effectiveInstances;
      for (final mergedInstance in effectiveInstances) {
        newestInstance = pickNewestInstance(newestInstance, mergedInstance);
      }
    }

    return (
      newInstances: newInstances,
      groupInstances: newGroupInstances,
      newestInstance: newestInstance,
      didInstancesChange: didInstancesChange,
    );
  }

  void _finalizeFetch(
    FetchProcessingResult processingResult,
    FetchExecutionResult executionResult,
    FetchContext context,
  ) {
    final nextNewestInstanceId =
        processingResult.newestInstance?.instance.instanceId;
    final nextGroupInstances = processingResult.didInstancesChange
        ? processingResult.groupInstances
        : executionResult.previousGroupInstances;
    final didErrorsChange = !collection_eq.areMapsEquivalent(
      executionResult.previousGroupErrors,
      executionResult.newGroupErrors,
    );
    final didNewestChange = state.newestInstanceId != nextNewestInstanceId;
    final totalInstances = nextGroupInstances.values.fold<int>(
      0,
      (sum, instances) => sum + instances.length,
    );

    if (processingResult.didInstancesChange ||
        didErrorsChange ||
        didNewestChange) {
      state = state.copyWith(
        groupInstances: nextGroupInstances,
        newestInstanceId: nextNewestInstanceId,
        groupErrors: didErrorsChange
            ? executionResult.newGroupErrors
            : executionResult.previousGroupErrors,
      );
    }

    _hasBaseline = true;
    _recordBaselineSuccess(
      polledGroupCount: context.selectedGroupIds.length,
      totalInstances: totalInstances,
    );
    _backoffDelay = 1;

    if (processingResult.newInstances.isNotEmpty) {
      AppLogger.info(
        'Found ${processingResult.newInstances.length} new instances',
        subCategory: 'group_monitor',
      );
    }
  }

  Future<void> _handleFetchError(
    Object e,
    StackTrace s,
    DateTime attemptAt,
  ) async {
    AppLogger.error(
      'Failed to fetch group instances',
      subCategory: 'group_monitor',
      error: e,
      stackTrace: s,
    );
    _recordBaselineSkip('error', attemptAt);
    await Future.delayed(Duration(seconds: _backoffDelay));
    _backoffDelay = (_backoffDelay * 2).clamp(1, AppConstants.maxBackoffDelay);
  }

  Future<void> _fetchUserGroupsInternal() async {
    if (_isFetchingGroups) {
      AppLogger.debug(
        'Group fetch already in progress, skipping duplicate call',
        subCategory: 'group_monitor',
      );
      return;
    }

    _isFetchingGroups = true;
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      AppLogger.debug('Fetching groups for user', subCategory: 'group_monitor');

      ref
          .read(apiCallCounterProvider.notifier)
          .incrementApiCall(lane: ApiRequestLane.userGroups);

      final api = ref.read(vrchatApiProvider);
      final response = await api.rawApi.getUsersApi().getUserGroups(
        userId: arg,
        extra: apiRequestLaneExtra(ApiRequestLane.userGroups),
      );
      final groups = response.data ?? [];

      AppLogger.info(
        'Fetched ${groups.length} groups',
        subCategory: 'group_monitor',
      );

      state = state.copyWith(
        allGroups: groups,
        isLoading: false,
        lastGroupsFetchTime: DateTime.now(),
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to fetch user groups',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to fetch groups: ${e.toString()}',
      );
    } finally {
      _isFetchingGroups = false;
    }
  }

  Future<void> _fetchUserGroupsIfNeededInternal({
    int minIntervalSeconds = 5,
  }) async {
    if (_isFetchingGroups) {
      AppLogger.debug(
        'Skipping fetch: group fetch already in progress',
        subCategory: 'group_monitor',
      );
      return;
    }

    if (state.lastGroupsFetchTime != null) {
      final timeSinceLastFetch = DateTime.now().difference(
        state.lastGroupsFetchTime!,
      );
      if (timeSinceLastFetch.inSeconds < minIntervalSeconds) {
        AppLogger.debug(
          'Skipping fetch: last fetch was ${timeSinceLastFetch.inSeconds}s ago',
          subCategory: 'group_monitor',
        );
        return;
      }
    }

    await _fetchUserGroupsInternal();
  }

  Future<bool> _ensureBoostActive() async {
    if (state.isBoostActive) {
      return true;
    }

    if (state.boostedGroupId != null || state.boostExpiresAt != null) {
      await _clearBoost(persist: true, logExpired: true);
    }
    return false;
  }

  Future<void> _fetchGroupInstancesInternal({
    bool bypassRateLimit = false,
  }) async {
    AppLogger.debug(
      'fetchGroupInstances() called',
      subCategory: 'group_monitor',
    );
    final attemptAt = DateTime.now();
    _recordBaselineAttempt(attemptAt);

    if (_validateFetchPreconditions(
          attemptAt: attemptAt,
          bypassRateLimit: bypassRateLimit,
        ) !=
        null) {
      return;
    }

    _baselineLoop.cancelTimer();

    final context = _prepareFetchContext(
      attemptAt: attemptAt,
      bypassRateLimit: bypassRateLimit,
    );
    if (context == null) {
      return;
    }

    _isFetchingBaseline = true;
    try {
      final executionResult = await _executeChunkedFetch(context);
      if (!executionResult.isMounted) {
        return;
      }
      final processingResult = await _processFetchResponses(
        executionResult,
        context,
      );
      _finalizeFetch(processingResult, executionResult, context);
    } catch (e, s) {
      await _handleFetchError(e, s, attemptAt);
    } finally {
      _isFetchingBaseline = false;
      if (ref.mounted) {
        _drainPendingRefreshesOrScheduleTicks();
      }
    }
  }

  Future<void> _fetchBoostedGroupInstancesInternal({
    bool bypassRateLimit = false,
  }) async {
    if (!_boostActive()) {
      _reconcileBoostLoop();
      return;
    }

    final isActive = await _ensureBoostActive();
    if (!isActive) {
      _reconcileBoostLoop();
      return;
    }

    final groupId = state.boostedGroupId;
    if (groupId == null) {
      return;
    }

    if (!state.selectedGroupIds.contains(groupId)) {
      await _clearBoost(persist: true, logExpired: false);
      return;
    }

    final decision = resolveRefreshRequestDecision(
      isInFlight: _isAnyFetchInFlight,
    );
    if (decision.shouldQueuePending) {
      _boostLoop.queuePending(bypassRateLimit: bypassRateLimit);
      AppLogger.debug(
        'Fetch already in progress, queueing pending boost refresh',
        subCategory: 'group_monitor',
      );
      if (state.boostedGroupId != null) {
        AppLogger.debug(
          'Boost poll skipped due to in-flight fetch for ${state.boostedGroupId}',
          subCategory: 'group_monitor',
        );
      }
      return;
    }

    _boostLoop.cancelTimer();

    if (RefreshCooldownHandler.shouldDeferForCooldown(
      ref: ref,
      bypassRateLimit: bypassRateLimit,
      lane: ApiRequestLane.groupBoost,
      logContext: 'group_monitor',
      fallbackDelay: Duration(seconds: _nextBoostPollDelaySeconds()),
      onDefer: (delay) => _scheduleNextBoostTick(overrideDelay: delay),
    )) {
      return;
    }

    _isBoostFetching = true;
    try {
      _boostPollCount += 1;
      final pollStart = DateTime.now();
      AppLogger.debug(
        'Boost poll #$_boostPollCount started for $groupId',
        subCategory: 'group_monitor',
      );

      ref
          .read(apiCallCounterProvider.notifier)
          .incrementApiCall(lane: ApiRequestLane.groupBoost);
      final api = ref.read(vrchatApiProvider);
      final response = await api.rawApi
          .getUsersApi()
          .getUserGroupInstancesForGroup(
            userId: arg,
            groupId: groupId,
            extra: apiRequestLaneExtra(ApiRequestLane.groupBoost),
          )
          .timeout(
            const Duration(
              seconds: AppConstants.groupInstancesRequestTimeoutSeconds,
            ),
          );
      if (!ref.mounted) {
        return;
      }

      final instances = response.data?.instances ?? [];
      final fetchedAt = response.data?.fetchedAt;
      final latencyMs = DateTime.now().difference(pollStart).inMilliseconds;
      AppLogger.debug(
        'Boost poll #$_boostPollCount for $groupId latency=${latencyMs}ms '
        'instances=${instances.length}'
        '${fetchedAt != null ? ' fetchedAt=$fetchedAt' : ''}',
        subCategory: 'group_monitor',
      );
      final previousInstances = state.groupInstances[groupId] ?? [];
      final previousGroupInstances = state.groupInstances;
      final previousGroupErrors = state.groupErrors;
      Duration? nextBoostFirstSeenAfter = state.boostFirstSeenAfter;
      var didBoostFirstSeenChange = false;

      if (!_boostFirstSeenLogged && instances.isNotEmpty) {
        final startedAt = _boostStartedAt;
        final delta = startedAt == null
            ? null
            : pollStart.difference(startedAt);
        AppLogger.info(
          'Boost first-seen for $groupId after '
          '${delta ?? Duration.zero} (instances=${instances.length})',
          subCategory: 'group_monitor',
        );
        _boostFirstSeenLogged = true;
        nextBoostFirstSeenAfter = delta;
        didBoostFirstSeenChange = state.boostFirstSeenAfter != delta;
      }

      await _attemptAutoInviteIfNewInstances(
        previousInstances: previousInstances,
        instances: instances,
        groupId: groupId,
        laneLabel: 'boosted group',
      );

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: groupId,
        fetchedInstances: instances,
        previousInstances: previousInstances,
        detectedAt: pollStart,
      );
      final newInstances = merged.newInstances;
      final mergedInstances = merged.effectiveInstances;

      if (newInstances.isNotEmpty) {
        _publishRelayHintForNewBoostedInstances(
          groupId: groupId,
          newInstances: newInstances,
          detectedAt: pollStart,
        );
      }

      var didGroupInstancesChange = false;
      Map<String, List<GroupInstanceWithGroup>> nextGroupInstances =
          previousGroupInstances;
      if (!identical(mergedInstances, previousInstances)) {
        didGroupInstancesChange = true;
        nextGroupInstances = Map<String, List<GroupInstanceWithGroup>>.from(
          previousGroupInstances,
        );
        nextGroupInstances[groupId] = mergedInstances;
      }

      var didGroupErrorsChange = false;
      Map<String, String> nextGroupErrors = previousGroupErrors;
      if (previousGroupErrors.containsKey(groupId)) {
        didGroupErrorsChange = true;
        nextGroupErrors = Map<String, String>.from(previousGroupErrors);
        nextGroupErrors.remove(groupId);
      }

      final nextNewestInstanceId = didGroupInstancesChange
          ? newestInstanceIdFromGroupInstances(nextGroupInstances)
          : state.newestInstanceId;
      final didNewestChange = nextNewestInstanceId != state.newestInstanceId;
      final didBoostDiagnosticsChange =
          state.boostPollCount != _boostPollCount ||
          state.lastBoostLatencyMs != latencyMs ||
          state.lastBoostFetchedAt != fetchedAt;

      if (didGroupInstancesChange ||
          didNewestChange ||
          didGroupErrorsChange ||
          didBoostDiagnosticsChange ||
          didBoostFirstSeenChange) {
        state = state.copyWith(
          groupInstances: nextGroupInstances,
          newestInstanceId: nextNewestInstanceId,
          groupErrors: nextGroupErrors,
          boostPollCount: _boostPollCount,
          lastBoostLatencyMs: latencyMs,
          lastBoostFetchedAt: fetchedAt,
          boostFirstSeenAfter: nextBoostFirstSeenAfter,
        );
      }

      _hasBaseline = true;

      if (newInstances.isNotEmpty) {
        AppLogger.info(
          'Found ${newInstances.length} new instances for boosted group',
          subCategory: 'group_monitor',
        );
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to fetch boosted group instances',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
      const errorMessage = 'Failed to fetch instances';
      if (state.groupErrors[groupId] != errorMessage) {
        final updatedGroupErrors = Map<String, String>.from(state.groupErrors);
        updatedGroupErrors[groupId] = errorMessage;
        state = state.copyWith(groupErrors: updatedGroupErrors);
      }
    } finally {
      _isBoostFetching = false;
      if (ref.mounted) {
        _reconcileRelayConnection();
        _drainPendingRefreshesOrScheduleTicks();
      }
    }
  }

  Future<void> _attemptAutoInviteIfNewInstances({
    required List<GroupInstanceWithGroup> previousInstances,
    required List<Instance> instances,
    required String groupId,
    required String laneLabel,
  }) async {
    if (previousInstances.isNotEmpty || instances.isEmpty) {
      return;
    }
    try {
      await _autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: groupId,
        enabled: state.autoInviteEnabled && state.isMonitoring,
        hasBaseline: _hasBaseline,
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to auto-invite for $laneLabel $groupId',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<World?> _fetchWorldDetailsInternal(String worldId) async {
    try {
      final api = ref.read(vrchatApiProvider);
      final response = await api.rawApi.getWorldsApi().getWorld(
        worldId: worldId,
      );
      return response.data;
    } catch (e, s) {
      AppLogger.error(
        'Failed to fetch world details',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }
}
