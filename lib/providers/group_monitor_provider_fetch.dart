// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
// Both suppressions are necessary because this part-file defines an extension
// on GroupMonitorNotifier and must access Riverpod's @protected `state` setter
// and `ref` property, which are legitimately available within the same library.

part of 'group_monitor_provider.dart';

typedef FetchContext = ({List<String> selectedGroupIds, DateTime attemptAt});

typedef FetchExecutionResult = ({
  GroupMonitorApi api,
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

typedef RefreshCyclePrepare<T> =
    FutureOr<T?> Function({
      required DateTime attemptAt,
      required bool bypassRateLimit,
    });

extension GroupMonitorFetchExtension on GroupMonitorNotifier {
  Future<void> _runRefreshCycle<T>({
    required DateTime attemptAt,
    required bool Function() isActive,
    required void Function() reconcile,
    required RefreshLoopController loop,
    required bool bypassRateLimit,
    required ApiRequestLane lane,
    required Duration fallbackDelay,
    required void Function({Duration? overrideDelay}) scheduleNextTick,
    required void Function(bool value) setFetchInFlight,
    required RefreshCyclePrepare<T> prepare,
    required Future<void> Function(T context) execute,
    Future<void> Function(Object e, StackTrace s, DateTime attemptAt)? onError,
    FutureOr<bool> Function()? beforeCooldown,
    void Function()? onQueuePending,
    void Function(Duration delay)? onCooldownDefer,
    void Function()? onFinallyMounted,
  }) async {
    if (!isActive()) {
      reconcile();
      return;
    }

    final decision = resolveRefreshRequestDecision(
      isInFlight: _isAnyFetchInFlight,
    );
    if (decision.shouldQueuePending) {
      loop.queuePending(bypassRateLimit: bypassRateLimit);
      onQueuePending?.call();
      return;
    }

    loop.cancelTimer();
    setFetchInFlight(true);

    try {
      if (beforeCooldown != null) {
        final shouldContinue = await beforeCooldown();
        if (!shouldContinue || !ref.mounted) {
          return;
        }
      }

      final handleCooldownDefer =
          onCooldownDefer ?? (delay) => scheduleNextTick(overrideDelay: delay);
      if (RefreshCooldownHandler.shouldDeferForCooldown(
        ref: ref,
        bypassRateLimit: bypassRateLimit,
        lane: lane,
        logContext: 'group_monitor',
        fallbackDelay: fallbackDelay,
        onDefer: handleCooldownDefer,
      )) {
        return;
      }

      final context = await prepare(
        attemptAt: attemptAt,
        bypassRateLimit: bypassRateLimit,
      );
      if (context == null || !ref.mounted) {
        return;
      }

      await execute(context);
    } catch (e, s) {
      if (!ref.mounted) {
        return;
      }
      if (onError != null) {
        await onError(e, s, attemptAt);
      } else {
        rethrow;
      }
    } finally {
      setFetchInFlight(false);
      if (ref.mounted) {
        onFinallyMounted?.call();
        _drainPendingRefreshesOrScheduleTicks();
      }
    }
  }

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
      fallbackDelay: _nextPollDelay(),
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

    final api = ref.read(groupMonitorApiProvider);
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
          return await api
              .getGroupInstances(
                groupId: groupId,
                lane: ApiRequestLane.groupBaseline,
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
    final retainedKeys = <String>{
      for (final groupResponse in responses)
        if (groupResponse.response != null)
          for (final groupInstance
              in groupResponse.response.data ?? const <GroupInstance>[])
            groupInstanceStableKey(
              worldId: groupInstance.world.id,
              instanceId: groupInstance.instanceId,
            ),
    };
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

      final instances = await _normalizeAndEnrichFetchedGroupInstances(
        groupId: groupId,
        groupInstances: response.data ?? const <GroupInstance>[],
        retainedKeys: retainedKeys,
        lane: ApiRequestLane.groupBaseline,
        laneLabel: 'baseline',
      );

      AppLogger.debug(
        'Group returned ${instances.length} instances',
        subCategory: 'group_monitor',
      );

      await _attemptAutoInviteIfNewInstances(
        previousInstances: previousInstances,
        instances: instances,
        groupId: groupId,
        lane: ApiRequestLane.groupBaseline,
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
    _pruneEnrichmentState(
      DateTime.now(),
      retainedKeys: _activeEnrichmentKeysFor(nextGroupInstances),
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

      final response = await ref
          .read(groupMonitorApiProvider)
          .getUserGroups(userId: arg);
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
    final expiresAt = state.boostExpiresAt;
    final boostIsCurrent =
        state.isBoostActive &&
        state.boostedGroupId != null &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now());
    if (boostIsCurrent) {
      return true;
    }

    if (state.boostedGroupId != null || expiresAt != null) {
      final logExpired =
          expiresAt != null && !expiresAt.isAfter(DateTime.now());
      await _clearBoost(persist: true, logExpired: logExpired);
    }
    return false;
  }

  Future<String?> _prepareBoostRefreshGroupId() async {
    final isActive = await _ensureBoostActive();
    if (!isActive) {
      _reconcileBoostLoop();
      return null;
    }

    final groupId = state.boostedGroupId;
    if (groupId == null) {
      return null;
    }

    if (!state.selectedGroupIds.contains(groupId)) {
      await _clearBoost(persist: true, logExpired: false);
      return null;
    }

    return groupId;
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

    await _runRefreshCycle<FetchContext>(
      attemptAt: attemptAt,
      isActive: _baselineActive,
      reconcile: _reconcileBaselineLoop,
      loop: _baselineLoop,
      bypassRateLimit: bypassRateLimit,
      lane: ApiRequestLane.groupBaseline,
      fallbackDelay: _nextPollDelay(),
      scheduleNextTick: _scheduleNextBaselineTick,
      setFetchInFlight: (value) => _isFetchingBaseline = value,
      prepare: _prepareFetchContext,
      execute: (context) async {
        final executionResult = await _executeChunkedFetch(context);
        if (!executionResult.isMounted) {
          return;
        }
        final processingResult = await _processFetchResponses(
          executionResult,
          context,
        );
        if (!ref.mounted) {
          return;
        }
        _finalizeFetch(processingResult, executionResult, context);
      },
      onError: _handleFetchError,
      onQueuePending: () => _recordBaselineSkip('in_flight_queue', attemptAt),
      onCooldownDefer: (delay) {
        _recordBaselineSkip('cooldown', attemptAt);
        _scheduleNextBaselineTick(overrideDelay: delay);
      },
    );
  }

  Future<void> _fetchBoostedGroupInstancesInternal({
    bool bypassRateLimit = false,
  }) async {
    final attemptAt = DateTime.now();
    await _runRefreshCycle<String>(
      attemptAt: attemptAt,
      isActive: _boostActive,
      reconcile: _reconcileBoostLoop,
      loop: _boostLoop,
      bypassRateLimit: bypassRateLimit,
      lane: ApiRequestLane.groupBoost,
      fallbackDelay: _nextBoostPollDelay(),
      scheduleNextTick: _scheduleNextBoostTick,
      setFetchInFlight: (value) => _isBoostFetching = value,
      beforeCooldown: () async => await _prepareBoostRefreshGroupId() != null,
      prepare:
          ({required DateTime attemptAt, required bool bypassRateLimit}) async {
            return _prepareBoostRefreshGroupId();
          },
      execute: (groupId) async {
        _boostPollCount += 1;
        final pollStart = DateTime.now();
        AppLogger.debug(
          'Boost poll #$_boostPollCount started for $groupId',
          subCategory: 'group_monitor',
        );

        ref
            .read(apiCallCounterProvider.notifier)
            .incrementApiCall(lane: ApiRequestLane.groupBoost);
        final api = ref.read(groupMonitorApiProvider);
        final response = await api
            .getGroupInstances(
              groupId: groupId,
              lane: ApiRequestLane.groupBoost,
            )
            .timeout(
              const Duration(
                seconds: AppConstants.groupInstancesRequestTimeoutSeconds,
              ),
            );
        if (!ref.mounted) {
          return;
        }

        final fetchedAt = DateTime.now();
        final instances = await _normalizeAndEnrichFetchedGroupInstances(
          groupId: groupId,
          groupInstances: response.data ?? const <GroupInstance>[],
          retainedKeys: {
            for (final groupInstance
                in response.data ?? const <GroupInstance>[])
              groupInstanceStableKey(
                worldId: groupInstance.world.id,
                instanceId: groupInstance.instanceId,
              ),
          },
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );
        final latencyMs = fetchedAt.difference(pollStart).inMilliseconds;
        AppLogger.debug(
          'Boost poll #$_boostPollCount for $groupId latency=${latencyMs}ms '
          'instances=${instances.length} fetchedAt=$fetchedAt',
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

        final resolvedAutoInviteTarget = await _attemptAutoInviteIfNewInstances(
          previousInstances: previousInstances,
          instances: instances,
          groupId: groupId,
          lane: ApiRequestLane.groupBoost,
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

        if (newInstances.isNotEmpty && resolvedAutoInviteTarget != null) {
          _publishRelayHintForNewBoostedInstances(
            target: resolvedAutoInviteTarget,
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
        _pruneEnrichmentState(
          DateTime.now(),
          retainedKeys: _activeEnrichmentKeysFor(nextGroupInstances),
        );

        if (newInstances.isNotEmpty) {
          AppLogger.info(
            'Found ${newInstances.length} new instances for boosted group',
            subCategory: 'group_monitor',
          );
        }
      },
      onError: (e, s, attemptAt) async {
        final groupId = state.boostedGroupId;
        AppLogger.error(
          'Failed to fetch boosted group instances',
          subCategory: 'group_monitor',
          error: e,
          stackTrace: s,
        );
        if (groupId == null) {
          return;
        }
        const errorMessage = 'Failed to fetch instances';
        if (state.groupErrors[groupId] != errorMessage) {
          final updatedGroupErrors = Map<String, String>.from(
            state.groupErrors,
          );
          updatedGroupErrors[groupId] = errorMessage;
          state = state.copyWith(groupErrors: updatedGroupErrors);
        }
      },
      onQueuePending: () {
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
      },
      onFinallyMounted: _reconcileRelayConnection,
    );
  }

  Future<GroupInstanceWithGroup?> _attemptAutoInviteIfNewInstances({
    required List<GroupInstanceWithGroup> previousInstances,
    required List<Instance> instances,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
  }) async {
    if (previousInstances.isNotEmpty || instances.isEmpty) {
      return null;
    }
    if (!(state.autoInviteEnabled && state.isMonitoring) || !_hasBaseline) {
      return null;
    }
    if (!state.isBoostActive ||
        state.boostedGroupId == null ||
        state.boostedGroupId != groupId) {
      return null;
    }
    try {
      final resolved = await _inviteCandidateResolver
          .resolveBestAutoInviteTarget(
            discoveryInstances: instances,
            groupId: groupId,
            lane: lane,
            laneLabel: laneLabel,
          );
      if (!ref.mounted) {
        return null;
      }
      if (resolved == null) {
        AppLogger.debug(
          'Auto-invite skipped for $laneLabel $groupId: no eligible target',
          subCategory: 'group_monitor',
        );
        return null;
      }

      final enabled =
          state.autoInviteEnabled &&
          state.isMonitoring &&
          state.isBoostActive &&
          state.boostedGroupId == groupId;
      if (!enabled || !_hasBaseline) {
        AppLogger.debug(
          'Auto-invite skipped for $laneLabel $groupId: '
          'state changed before invite dispatch',
          subCategory: 'group_monitor',
        );
        return null;
      }

      await _autoInviteService.attemptAutoInviteTarget(
        target: resolved,
        enabled: enabled,
        hasBaseline: _hasBaseline,
      );
      return resolved;
    } catch (e, s) {
      AppLogger.error(
        'Failed to auto-invite for $laneLabel $groupId',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  Future<List<Instance>> _normalizeAndEnrichFetchedGroupInstances({
    required String groupId,
    required List<GroupInstance> groupInstances,
    required Set<String> retainedKeys,
    required ApiRequestLane lane,
    required String laneLabel,
  }) async {
    final effectiveRetainedKeys = <String>{
      ..._activeEnrichmentKeysFor(state.groupInstances),
      ...retainedKeys,
    };
    return _inviteCandidateResolver.normalizeAndEnrichFetchedGroupInstances(
      groupInstances: groupInstances,
      groupId: groupId,
      retainedKeys: effectiveRetainedKeys,
      lane: lane,
      laneLabel: laneLabel,
    );
  }

  void _pruneEnrichmentState(
    DateTime now, {
    Set<String> retainedKeys = const {},
  }) {
    _inviteCandidateResolver.pruneState(
      now,
      retainedKeys: <String>{
        ..._activeEnrichmentKeysFor(state.groupInstances),
        ...retainedKeys,
      },
    );
  }

  Set<String> _activeEnrichmentKeysFor(
    Map<String, List<GroupInstanceWithGroup>> groupInstances,
  ) {
    return <String>{
      for (final groupEntries in groupInstances.values)
        for (final entry in groupEntries)
          groupInstanceStableKey(
            worldId: entry.instance.worldId,
            instanceId: entry.instance.instanceId,
          ),
    };
  }

  Future<World?> _fetchWorldDetailsInternal(String worldId) async {
    try {
      final response = await ref
          .read(groupMonitorApiProvider)
          .getWorld(worldId: worldId);
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
