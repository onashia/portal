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
        api: executionResult.api,
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
      if (!ref.mounted) {
        return;
      }
      _finalizeFetch(processingResult, executionResult, context);
    } catch (e, s) {
      if (!ref.mounted) {
        return;
      }
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
      final api = ref.read(groupMonitorApiProvider);
      final response = await api
          .getGroupInstances(groupId: groupId, lane: ApiRequestLane.groupBoost)
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
        api: api,
        groupId: groupId,
        groupInstances: response.data ?? const <GroupInstance>[],
        retainedKeys: {
          for (final groupInstance in response.data ?? const <GroupInstance>[])
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
      final result = await _autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: groupId,
        enabled: state.autoInviteEnabled && state.isMonitoring,
        hasBaseline: _hasBaseline,
      );
      if (result == null) {
        AppLogger.debug(
          'Auto-invite skipped for $laneLabel $groupId: no eligible target',
          subCategory: 'group_monitor',
        );
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to auto-invite for $laneLabel $groupId',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<List<Instance>> _normalizeAndEnrichFetchedGroupInstances({
    required GroupMonitorApi api,
    required String groupId,
    required List<GroupInstance> groupInstances,
    required Set<String> retainedKeys,
    required ApiRequestLane lane,
    required String laneLabel,
  }) async {
    final now = DateTime.now();
    _pruneEnrichmentState(now, retainedKeys: retainedKeys);

    var instances = groupInstances
        .map(
          (groupInstance) => normalizeGroupInstance(
            groupInstance: groupInstance,
            groupId: groupId,
            enrichedInstance: _cachedEnrichedInstance(
              worldId: groupInstance.world.id,
              instanceId: groupInstance.instanceId,
              now: now,
            ),
          ),
        )
        .toList(growable: false);

    instances = await _enrichBestCandidateIfNeeded(
      api: api,
      instances: instances,
      groupId: groupId,
      lane: lane,
      laneLabel: laneLabel,
    );
    return instances;
  }

  Future<List<Instance>> _enrichBestCandidateIfNeeded({
    required GroupMonitorApi api,
    required List<Instance> instances,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
  }) async {
    if (instances.isEmpty) {
      return instances;
    }

    Instance? best;
    for (final candidate in instances) {
      if (best == null || candidate.nUsers > best.nUsers) {
        best = candidate;
      }
    }
    if (best == null || best.worldId.isEmpty || best.instanceId.isEmpty) {
      AppLogger.debug(
        'Skipping instance enrichment for $groupId ($laneLabel): '
        'highest-population candidate has invalid identifiers',
        subCategory: 'group_monitor',
      );
      return instances;
    }

    final now = DateTime.now();
    final key = groupInstanceStableKey(
      worldId: best.worldId,
      instanceId: best.instanceId,
    );
    final cachedEntry = _enrichedInstanceByKey[key];
    if (cachedEntry != null &&
        now.difference(cachedEntry.fetchedAt) >
            const Duration(
              seconds: AppConstants.groupInstanceEnrichmentTtlSeconds,
            )) {
      _enrichedInstanceByKey.remove(key);
      AppLogger.debug(
        'Re-enriching instance after cache expiry for $groupId '
        '${best.worldId}:${best.instanceId} ($laneLabel)',
        subCategory: 'group_monitor',
      );
    }

    if (_cachedEnrichedInstance(
          worldId: best.worldId,
          instanceId: best.instanceId,
          now: now,
        ) !=
        null) {
      AppLogger.debug(
        'Instance enrichment cache hit for $groupId '
        '${best.worldId}:${best.instanceId} ($laneLabel)',
        subCategory: 'group_monitor',
      );
      return instances;
    }

    final blockedUntil = _enrichmentFailureUntilByKey[key];
    if (blockedUntil != null && blockedUntil.isAfter(now)) {
      AppLogger.debug(
        'Skipping instance enrichment due to cooldown for $groupId '
        '${best.worldId}:${best.instanceId} ($laneLabel)',
        subCategory: 'group_monitor',
      );
      return instances;
    }

    AppLogger.debug(
      'Enriching best instance for $groupId ${best.worldId}:${best.instanceId} '
      '($laneLabel)',
      subCategory: 'group_monitor',
    );

    ref.read(apiCallCounterProvider.notifier).incrementApiCall(lane: lane);
    try {
      final response = await api
          .getInstance(
            worldId: best.worldId,
            instanceId: best.instanceId,
            lane: lane,
          )
          .timeout(
            const Duration(
              seconds: AppConstants.groupInstancesRequestTimeoutSeconds,
            ),
          );

      final enriched = response.data;
      if (enriched == null) {
        _recordEnrichmentFailure(
          key: key,
          groupId: groupId,
          instance: best,
          laneLabel: laneLabel,
          reason: 'empty_response',
        );
        return instances;
      }

      _enrichedInstanceByKey[key] = (instance: enriched, fetchedAt: now);
      _enrichmentFailureUntilByKey.remove(key);
      AppLogger.info(
        'Instance enrichment succeeded for $groupId '
        '${best.worldId}:${best.instanceId} ($laneLabel)',
        subCategory: 'group_monitor',
      );

      final nextInstances = instances.toList(growable: false);
      final index = nextInstances.indexWhere(
        (candidate) =>
            candidate.worldId == best!.worldId &&
            candidate.instanceId == best.instanceId,
      );
      if (index == -1) {
        return instances;
      }
      nextInstances[index] = mergeDiscoveryInstanceWithEnrichment(
        discoveryInstance: nextInstances[index],
        enrichedInstance: enriched,
        groupId: groupId,
      );
      return nextInstances;
    } on DioException catch (e, s) {
      final statusCode = e.response?.statusCode;
      _recordEnrichmentFailure(
        key: key,
        groupId: groupId,
        instance: best,
        laneLabel: laneLabel,
        reason: statusCode == null ? e.type.name : 'status_$statusCode',
        error: e,
        stackTrace: s,
      );
      return instances;
    } catch (e, s) {
      _recordEnrichmentFailure(
        key: key,
        groupId: groupId,
        instance: best,
        laneLabel: laneLabel,
        reason: 'unexpected',
        error: e,
        stackTrace: s,
      );
      return instances;
    }
  }

  Instance? _cachedEnrichedInstance({
    required String worldId,
    required String instanceId,
    required DateTime now,
  }) {
    final key = groupInstanceStableKey(
      worldId: worldId,
      instanceId: instanceId,
    );
    final cached = _enrichedInstanceByKey[key];
    if (cached == null) {
      return null;
    }

    final ttl = Duration(
      seconds: AppConstants.groupInstanceEnrichmentTtlSeconds,
    );
    if (now.difference(cached.fetchedAt) > ttl) {
      _enrichedInstanceByKey.remove(key);
      return null;
    }

    return cached.instance;
  }

  void _recordEnrichmentFailure({
    required String key,
    required String groupId,
    required Instance instance,
    required String laneLabel,
    required String reason,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final now = DateTime.now();
    _enrichmentFailureUntilByKey[key] = now.add(
      const Duration(
        seconds: AppConstants.groupInstanceEnrichmentFailureCooldownSeconds,
      ),
    );

    final logKey = '$laneLabel|$key|$reason';
    final dedupeTtl = const Duration(
      seconds: AppConstants.groupInstanceEnrichmentLogDedupeSeconds,
    );
    if (_enrichmentFailureLogDedupe.isBlocked(logKey, now)) {
      return;
    }
    _enrichmentFailureLogDedupe.record(logKey, now: now, ttl: dedupeTtl);

    final message =
        'Instance enrichment failed for $groupId '
        '${instance.worldId}:${instance.instanceId} ($laneLabel, reason=$reason)';
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final isTransient =
          statusCode == null ||
          statusCode == 404 ||
          statusCode == 409 ||
          statusCode == 429 ||
          statusCode >= 500;
      if (isTransient) {
        AppLogger.warning(message, subCategory: 'group_monitor');
        return;
      }
    }

    AppLogger.error(
      message,
      subCategory: 'group_monitor',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _pruneEnrichmentState(
    DateTime now, {
    Set<String> retainedKeys = const {},
  }) {
    _enrichmentFailureLogDedupe.prune(now);
    _enrichmentFailureUntilByKey.removeWhere(
      (_, blockedUntil) => !blockedUntil.isAfter(now),
    );
    _enrichedInstanceByKey.removeWhere(
      (_, cached) =>
          now.difference(cached.fetchedAt) >
          const Duration(
            seconds: AppConstants.groupInstanceEnrichmentTtlSeconds,
          ),
    );

    final activeKeys = <String>{
      ..._activeEnrichmentKeysFor(state.groupInstances),
      ...retainedKeys,
    };
    _enrichedInstanceByKey.removeWhere((key, _) => !activeKeys.contains(key));
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
