import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/app_constants.dart';
import '../models/group_instance_with_group.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../services/invite_service.dart';
import '../utils/app_logger.dart';
import 'api_call_counter.dart';
import 'api_rate_limit_provider.dart';
import 'auth_provider.dart';
import 'group_monitor_state.dart';
import 'group_monitor_storage.dart';
import 'polling_lifecycle.dart';

export 'group_monitor_state.dart';

final DateTime _stableTimestampFallback = DateTime.fromMillisecondsSinceEpoch(
  0,
);

DateTime _normalizedDetectedAt(DateTime? dateTime) =>
    dateTime ?? _stableTimestampFallback;

int _compareInstancesByDetectedDesc(
  GroupInstanceWithGroup a,
  GroupInstanceWithGroup b,
) {
  final byTime = _normalizedDetectedAt(
    b.firstDetectedAt,
  ).compareTo(_normalizedDetectedAt(a.firstDetectedAt));
  if (byTime != 0) {
    return byTime;
  }

  final byGroup = a.groupId.compareTo(b.groupId);
  if (byGroup != 0) {
    return byGroup;
  }

  return a.instance.instanceId.compareTo(b.instance.instanceId);
}

GroupInstanceWithGroup? _pickNewestInstance(
  GroupInstanceWithGroup? current,
  GroupInstanceWithGroup candidate,
) {
  if (current == null) {
    return candidate;
  }

  return _compareInstancesByDetectedDesc(candidate, current) < 0
      ? candidate
      : current;
}

@visibleForTesting
({
  String? boostedGroupId,
  DateTime? boostExpiresAt,
  bool shouldClear,
  bool logExpired,
})
resolveLoadedBoostSettings({
  required GroupMonitorBoostSettings settings,
  required DateTime now,
}) {
  final boostedGroupId = settings.groupId;
  final boostExpiresAt = settings.expiresAt;

  if (boostedGroupId != null && boostExpiresAt != null) {
    if (boostExpiresAt.isAfter(now)) {
      return (
        boostedGroupId: boostedGroupId,
        boostExpiresAt: boostExpiresAt,
        shouldClear: false,
        logExpired: false,
      );
    }

    return (
      boostedGroupId: null,
      boostExpiresAt: null,
      shouldClear: true,
      logExpired: true,
    );
  }

  if (boostedGroupId != null || boostExpiresAt != null) {
    return (
      boostedGroupId: null,
      boostExpiresAt: null,
      shouldClear: true,
      logExpired: false,
    );
  }

  return (
    boostedGroupId: null,
    boostExpiresAt: null,
    shouldClear: false,
    logExpired: false,
  );
}

@visibleForTesting
({
  List<GroupInstanceWithGroup> mergedInstances,
  List<GroupInstanceWithGroup> newInstances,
})
mergeFetchedGroupInstances({
  required String groupId,
  required List<Instance> fetchedInstances,
  required List<GroupInstanceWithGroup> previousInstances,
  required DateTime detectedAt,
}) {
  final previousInstancesById = {
    for (final previous in previousInstances)
      previous.instance.instanceId: previous,
  };

  final mergedInstances = <GroupInstanceWithGroup>[];
  final newInstances = <GroupInstanceWithGroup>[];

  for (final fetched in fetchedInstances) {
    final previous = previousInstancesById[fetched.instanceId];
    final merged = GroupInstanceWithGroup(
      instance: fetched,
      groupId: groupId,
      firstDetectedAt: previous?.firstDetectedAt ?? detectedAt,
    );
    mergedInstances.add(merged);
    if (previous == null) {
      newInstances.add(merged);
    }
  }

  return (mergedInstances: mergedInstances, newInstances: newInstances);
}

({
  List<GroupInstanceWithGroup> effectiveInstances,
  List<GroupInstanceWithGroup> newInstances,
  bool didChange,
})
_mergeFetchedGroupInstancesWithDiff({
  required String groupId,
  required List<Instance> fetchedInstances,
  required List<GroupInstanceWithGroup> previousInstances,
  required DateTime detectedAt,
}) {
  final previousByInstanceId = <String, GroupInstanceWithGroup>{
    for (final previous in previousInstances)
      previous.instance.instanceId: previous,
  };

  var didChange =
      fetchedInstances.length != previousInstances.length ||
      previousByInstanceId.length != previousInstances.length;
  final mergedInstances = <GroupInstanceWithGroup>[];
  final newInstances = <GroupInstanceWithGroup>[];
  final fetchedInstanceIds = <String>{};

  for (final fetched in fetchedInstances) {
    fetchedInstanceIds.add(fetched.instanceId);
    final previous = previousByInstanceId[fetched.instanceId];
    final merged = GroupInstanceWithGroup(
      instance: fetched,
      groupId: groupId,
      firstDetectedAt: previous?.firstDetectedAt ?? detectedAt,
    );
    mergedInstances.add(merged);

    if (previous == null) {
      newInstances.add(merged);
      didChange = true;
      continue;
    }

    if (!areGroupInstanceEntriesEquivalent(previous, merged)) {
      didChange = true;
    }
  }

  for (final previousId in previousByInstanceId.keys) {
    if (!fetchedInstanceIds.contains(previousId)) {
      didChange = true;
      break;
    }
  }

  return (
    effectiveInstances: didChange ? mergedInstances : previousInstances,
    newInstances: newInstances,
    didChange: didChange,
  );
}

@visibleForTesting
({
  List<GroupInstanceWithGroup> effectiveInstances,
  List<GroupInstanceWithGroup> newInstances,
  bool didChange,
})
mergeFetchedGroupInstancesWithDiffForTesting({
  required String groupId,
  required List<Instance> fetchedInstances,
  required List<GroupInstanceWithGroup> previousInstances,
  required DateTime detectedAt,
}) {
  return _mergeFetchedGroupInstancesWithDiff(
    groupId: groupId,
    fetchedInstances: fetchedInstances,
    previousInstances: previousInstances,
    detectedAt: detectedAt,
  );
}

@visibleForTesting
bool areGroupInstanceEntriesEquivalent(
  GroupInstanceWithGroup previous,
  GroupInstanceWithGroup next,
) {
  return previous.instance.instanceId == next.instance.instanceId &&
      previous.instance.worldId == next.instance.worldId &&
      previous.instance.world.name == next.instance.world.name &&
      previous.instance.nUsers == next.instance.nUsers &&
      previous.firstDetectedAt == next.firstDetectedAt;
}

@visibleForTesting
bool areGroupInstanceListsEquivalent(
  List<GroupInstanceWithGroup> previous,
  List<GroupInstanceWithGroup> next,
) {
  if (identical(previous, next)) {
    return true;
  }

  if (previous.length != next.length) {
    return false;
  }

  final previousByInstanceId = <String, GroupInstanceWithGroup>{
    for (final entry in previous) entry.instance.instanceId: entry,
  };

  if (previousByInstanceId.length != previous.length) {
    return false;
  }

  final seenInstanceIds = <String>{};
  for (final nextEntry in next) {
    final instanceId = nextEntry.instance.instanceId;
    if (!seenInstanceIds.add(instanceId)) {
      return false;
    }

    final previousEntry = previousByInstanceId[instanceId];
    if (previousEntry == null ||
        !areGroupInstanceEntriesEquivalent(previousEntry, nextEntry)) {
      return false;
    }
  }

  return true;
}

@visibleForTesting
bool areGroupInstancesByGroupEquivalent(
  Map<String, List<GroupInstanceWithGroup>> previous,
  Map<String, List<GroupInstanceWithGroup>> next,
) {
  if (identical(previous, next)) {
    return true;
  }

  if (previous.length != next.length) {
    return false;
  }

  for (final entry in previous.entries) {
    final nextGroupInstances = next[entry.key];
    if (nextGroupInstances == null ||
        !areGroupInstanceListsEquivalent(entry.value, nextGroupInstances)) {
      return false;
    }
  }

  return true;
}

bool _areStringMapsEquivalent(
  Map<String, String> previous,
  Map<String, String> next,
) {
  if (identical(previous, next)) {
    return true;
  }

  if (previous.length != next.length) {
    return false;
  }

  for (final entry in previous.entries) {
    if (next[entry.key] != entry.value) {
      return false;
    }
  }

  return true;
}

@visibleForTesting
bool hasGroupInstanceKeyMismatch({
  required Set<String> selectedGroupIds,
  required Map<String, List<GroupInstanceWithGroup>> groupInstances,
}) {
  if (groupInstances.length != selectedGroupIds.length) {
    return true;
  }

  for (final groupId in groupInstances.keys) {
    if (!selectedGroupIds.contains(groupId)) {
      return true;
    }
  }

  return false;
}

@visibleForTesting
({List<GroupInstanceWithGroup> effectiveInstances, bool didChange})
resolveGroupInstancesForGroup({
  required List<GroupInstanceWithGroup> previousInstances,
  required List<GroupInstanceWithGroup> mergedInstances,
}) {
  final didChange = !areGroupInstanceListsEquivalent(
    previousInstances,
    mergedInstances,
  );
  return (
    effectiveInstances: didChange ? mergedInstances : previousInstances,
    didChange: didChange,
  );
}

@visibleForTesting
Map<String, List<GroupInstanceWithGroup>> selectGroupInstancesForState({
  required bool didInstancesChange,
  required Map<String, List<GroupInstanceWithGroup>> previousGroupInstances,
  required Map<String, List<GroupInstanceWithGroup>> nextGroupInstances,
}) {
  return didInstancesChange ? nextGroupInstances : previousGroupInstances;
}

@visibleForTesting
Future<List<({String groupId, T? response})>> fetchGroupInstancesChunked<T>({
  required List<String> orderedGroupIds,
  required Future<T?> Function(String groupId) fetchGroupInstances,
  int maxConcurrentRequests = AppConstants.groupInstancesMaxConcurrentRequests,
}) async {
  if (maxConcurrentRequests < 1) {
    throw ArgumentError.value(
      maxConcurrentRequests,
      'maxConcurrentRequests',
      'must be at least 1',
    );
  }

  final results = <({String groupId, T? response})>[];

  for (
    int start = 0;
    start < orderedGroupIds.length;
    start += maxConcurrentRequests
  ) {
    final end = math.min(start + maxConcurrentRequests, orderedGroupIds.length);
    final chunk = orderedGroupIds.sublist(start, end);
    final chunkResults = await Future.wait(
      chunk.map((groupId) async {
        final response = await fetchGroupInstances(groupId);
        return (groupId: groupId, response: response);
      }),
    );
    results.addAll(chunkResults);
  }

  return results;
}

@visibleForTesting
bool shouldQueuePendingBoostPoll({
  required bool isFetching,
  required bool isMonitoring,
  required bool isBoostActive,
}) {
  return isFetching && isMonitoring && isBoostActive;
}

@visibleForTesting
bool shouldDrainPendingBoostPoll({
  required bool pendingBoostPoll,
  required bool isMonitoring,
  required bool isBoostActive,
  required bool isFetching,
}) {
  return pendingBoostPoll && isMonitoring && isBoostActive && !isFetching;
}

bool canPollForUserSession({
  required bool isAuthenticated,
  required String? authenticatedUserId,
  required String expectedUserId,
}) {
  return isSessionEligible(
    isAuthenticated: isAuthenticated,
    authenticatedUserId: authenticatedUserId,
    expectedUserId: expectedUserId,
  );
}

@visibleForTesting
List<GroupInstanceWithGroup> sortGroupInstances(
  Iterable<GroupInstanceWithGroup> instances,
) {
  final sorted = instances.toList(growable: false);
  sorted.sort(_compareInstancesByDetectedDesc);
  return sorted;
}

@visibleForTesting
String? newestInstanceIdFromGroupInstances(
  Map<String, List<GroupInstanceWithGroup>> groupInstances,
) {
  GroupInstanceWithGroup? newest;

  for (final groupEntries in groupInstances.values) {
    for (final instance in groupEntries) {
      newest = _pickNewestInstance(newest, instance);
    }
  }

  return newest?.instance.instanceId;
}

class GroupMonitorNotifier extends Notifier<GroupMonitorState> {
  final String arg;

  GroupMonitorNotifier(this.arg);

  bool _canPollForCurrentSession() {
    final session = ref.read(authSessionSnapshotProvider);
    return canPollForUserSession(
      isAuthenticated: session.isAuthenticated,
      authenticatedUserId: session.userId,
      expectedUserId: arg,
    );
  }

  @override
  GroupMonitorState build() {
    _listenForAuthChanges();
    ref.onDispose(() {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      _boostPollingTimer?.cancel();
      _boostPollingTimer = null;
      _selectionRefreshDebounceTimer?.cancel();
      _selectionRefreshDebounceTimer = null;
      _pendingBaselineRefresh = false;
      _pendingBaselineBypassRateLimit = false;
      _pendingBoostRefresh = false;
      _pendingBoostBypassRateLimit = false;
    });
    _loadSelectedGroups();
    _loadAutoInviteSetting();
    _loadBoostSettings();
    return const GroupMonitorState(isLoading: true);
  }

  void _listenForAuthChanges() {
    ref.listen<AuthSessionSnapshot>(authSessionSnapshotProvider, (
      previous,
      next,
    ) {
      final wasEligible =
          previous?.isAuthenticated == true && previous?.userId == arg;
      final isEligible = next.isAuthenticated && next.userId == arg;

      if (!isEligible) {
        if (state.isMonitoring) {
          stopMonitoring();
        } else {
          _reconcileBaselineLoop();
          _reconcileBoostLoop();
        }
        return;
      }

      if (!wasEligible) {
        Future.microtask(() {
          if (!ref.mounted) {
            return;
          }
          _reconcileMonitoringForSelectionState();
        });
        return;
      }

      _reconcileBaselineLoop();
      _reconcileBoostLoop();
    });
  }

  Future<void> _loadBoostSettings() async {
    try {
      final settings = await GroupMonitorStorage.loadBoostSettings();
      final resolved = resolveLoadedBoostSettings(
        settings: settings,
        now: DateTime.now(),
      );

      if (resolved.shouldClear) {
        await _clearBoost(persist: true, logExpired: resolved.logExpired);
        return;
      }

      if (resolved.boostedGroupId != null && resolved.boostExpiresAt != null) {
        state = state.copyWith(
          boostedGroupId: resolved.boostedGroupId,
          boostExpiresAt: resolved.boostExpiresAt,
        );
        AppLogger.debug(
          'Loaded active boost settings for ${resolved.boostedGroupId}',
          subCategory: 'group_monitor',
        );

        if (state.isMonitoring) {
          _requestBoostRefresh(immediate: true);
        }
      }
    } catch (e) {
      AppLogger.error(
        'Failed to load boost settings',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> _loadAutoInviteSetting() async {
    try {
      final enabled = await GroupMonitorStorage.loadAutoInviteEnabled();
      state = state.copyWith(autoInviteEnabled: enabled);
      AppLogger.debug(
        'Loaded auto-invite setting: $enabled',
        subCategory: 'group_monitor',
      );
    } catch (e) {
      AppLogger.error(
        'Failed to load auto-invite setting',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> _loadSelectedGroups() async {
    try {
      final selectedIds = await GroupMonitorStorage.loadSelectedGroupIds();
      final loadedSelection = selectedIds.toSet();
      final shouldApplyLoadedSelection = state.selectedGroupIds.isEmpty;
      if (shouldApplyLoadedSelection) {
        state = state.copyWith(selectedGroupIds: loadedSelection);
      } else {
        AppLogger.debug(
          'Skipping loaded selected groups because selection already changed in memory',
          subCategory: 'group_monitor',
        );
      }
      AppLogger.debug(
        'Loaded ${selectedIds.length} selected groups from storage',
        subCategory: 'group_monitor',
      );
      _reconcileMonitoringForSelectionState();
    } catch (e) {
      AppLogger.error(
        'Failed to load selected groups',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> toggleAutoInvite() async {
    final newValue = !state.autoInviteEnabled;
    state = state.copyWith(autoInviteEnabled: newValue);
    try {
      await GroupMonitorStorage.saveAutoInviteEnabled(newValue);
      AppLogger.info(
        'Auto-invite set to $newValue',
        subCategory: 'group_monitor',
      );
    } catch (e) {
      AppLogger.error(
        'Failed to save auto-invite setting',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> setBoostedGroup(String? groupId) async {
    if (groupId == null || groupId.isEmpty) {
      await _clearBoost(persist: true, logExpired: false);
      return;
    }

    if (!state.isMonitoring) {
      AppLogger.warning(
        'Cannot enable boost while monitoring is off',
        subCategory: 'group_monitor',
      );
      return;
    }

    if (groupId == state.boostedGroupId && state.isBoostActive) {
      await _clearBoost(persist: true, logExpired: false);
      return;
    }

    if (!state.selectedGroupIds.contains(groupId)) {
      AppLogger.warning(
        'Cannot boost unselected group $groupId',
        subCategory: 'group_monitor',
      );
      return;
    }

    final expiresAt = DateTime.now().add(
      const Duration(minutes: AppConstants.boostDurationMinutes),
    );
    _boostStartedAt = DateTime.now();
    _boostPollCount = 0;
    _boostFirstSeenLogged = false;
    state = state.copyWith(
      boostedGroupId: groupId,
      boostExpiresAt: expiresAt,
      boostPollCount: 0,
      lastBoostLatencyMs: null,
      lastBoostFetchedAt: null,
      boostFirstSeenAfter: null,
    );
    await _persistBoostSettings(groupId: groupId, boostExpiresAt: expiresAt);
    AppLogger.info(
      'Boosted group set to $groupId',
      subCategory: 'group_monitor',
    );

    if (state.isMonitoring) {
      _requestBoostRefresh(immediate: true);
    }
  }

  Future<void> clearBoost() async {
    await _clearBoost(persist: true, logExpired: false);
  }

  Future<void> toggleBoostForGroup(String groupId) async {
    if (state.boostedGroupId == groupId) {
      await clearBoost();
    } else {
      await setBoostedGroup(groupId);
    }
  }

  Future<void> _clearBoost({
    required bool persist,
    required bool logExpired,
    bool requestBaselineRecovery = true,
  }) async {
    final hadBoost =
        state.boostedGroupId != null || state.boostExpiresAt != null;
    _boostPollingTimer?.cancel();
    _boostPollingTimer = null;
    _pendingBoostRefresh = false;
    _boostStartedAt = null;
    _boostPollCount = 0;
    _boostFirstSeenLogged = false;
    state = state.copyWith(
      boostedGroupId: null,
      boostExpiresAt: null,
      boostPollCount: 0,
      lastBoostLatencyMs: null,
      lastBoostFetchedAt: null,
      boostFirstSeenAfter: null,
    );

    if (persist) {
      await _persistBoostSettings(groupId: null, boostExpiresAt: null);
    }

    if (logExpired) {
      AppLogger.info(
        'Boost expired, reverting to normal polling',
        subCategory: 'group_monitor',
      );
    }

    if (requestBaselineRecovery &&
        hadBoost &&
        state.isMonitoring &&
        state.selectedGroupIds.isNotEmpty) {
      _requestBaselineRefresh(immediate: true);
    }
  }

  Future<void> _persistBoostSettings({
    required String? groupId,
    required DateTime? boostExpiresAt,
  }) async {
    try {
      await GroupMonitorStorage.saveBoostSettings(
        groupId: groupId,
        boostExpiresAt: boostExpiresAt,
      );
    } catch (e) {
      AppLogger.error(
        'Failed to persist boost settings',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> _saveSelectedGroups() async {
    try {
      await GroupMonitorStorage.saveSelectedGroupIds(state.selectedGroupIds);
    } catch (e) {
      AppLogger.error(
        'Failed to save selected groups',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> fetchUserGroups() async {
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

  Future<void> fetchUserGroupsIfNeeded({int minIntervalSeconds = 5}) async {
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

    await fetchUserGroups();
  }

  void toggleGroupSelection(String groupId) {
    final wasMonitoring = state.isMonitoring;
    final newSelection = Set<String>.from(state.selectedGroupIds);
    final wasSelected = newSelection.contains(groupId);
    final newGroupInstances = Map<String, List<GroupInstanceWithGroup>>.from(
      state.groupInstances,
    );
    final newGroupErrors = Map<String, String>.from(state.groupErrors);

    if (wasSelected) {
      newSelection.remove(groupId);
      // Clear cached data for deselected group to free memory
      newGroupInstances.remove(groupId);
      newGroupErrors.remove(groupId);
      if (state.boostedGroupId == groupId) {
        unawaited(_clearBoost(persist: true, logExpired: false));
      }
    } else {
      newSelection.add(groupId);
    }

    state = state.copyWith(
      selectedGroupIds: newSelection,
      groupInstances: newGroupInstances,
      groupErrors: newGroupErrors,
    );
    _reconcileMonitoringForSelectionState();
    if (!wasSelected && wasMonitoring && state.isMonitoring) {
      _scheduleSelectionTriggeredBaselineRefresh();
    }
    _saveSelectedGroups();
    AppLogger.debug(
      'Toggled group, now ${newSelection.length} selected',
      subCategory: 'group_monitor',
    );
  }

  Timer? _pollingTimer;
  Timer? _boostPollingTimer;
  Timer? _selectionRefreshDebounceTimer;
  int _backoffDelay = 1;
  bool _isFetchingBaseline = false;
  bool _isBoostFetching = false;
  bool _isFetchingGroups = false;
  bool _pendingBaselineRefresh = false;
  bool _pendingBaselineBypassRateLimit = false;
  bool _pendingBoostRefresh = false;
  bool _pendingBoostBypassRateLimit = false;
  bool _hasBaseline = false;
  DateTime? _boostStartedAt;
  int _boostPollCount = 0;
  bool _boostFirstSeenLogged = false;
  final _random = math.Random();

  @visibleForTesting
  bool get hasActivePollingTimer => _pollingTimer != null;

  bool get _isAnyFetchInFlight => _isFetchingBaseline || _isBoostFetching;

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
    _pendingBaselineRefresh = true;
    _pendingBaselineBypassRateLimit = false;
    _selectionRefreshDebounceTimer = Timer(
      AppConstants.selectionRefreshDebounceDuration,
      () {
        if (!ref.mounted) {
          return;
        }
        _selectionRefreshDebounceTimer = null;
        _pendingBaselineRefresh = false;
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
  }

  void _reconcileBaselineLoop() {
    if (!state.isMonitoring) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      _pendingBaselineRefresh = false;
      _pendingBaselineBypassRateLimit = false;
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

    if (_pollingTimer == null &&
        !_isAnyFetchInFlight &&
        !_pendingBaselineRefresh) {
      AppLogger.debug(
        'Baseline polling timer missing while monitoring is active; rescheduling',
        subCategory: 'group_monitor',
      );
      _requestBaselineRefresh(immediate: true);
    }
  }

  void _reconcileBoostLoop() {
    if (!_boostActive()) {
      _boostPollingTimer?.cancel();
      _boostPollingTimer = null;
      _pendingBoostRefresh = false;
      _pendingBoostBypassRateLimit = false;
      return;
    }

    if (_boostPollingTimer == null &&
        !_isAnyFetchInFlight &&
        !_pendingBoostRefresh) {
      _requestBoostRefresh(immediate: true);
    }
  }

  int _nextPollDelaySeconds() {
    final base = AppConstants.pollingIntervalSeconds;
    final jitter = AppConstants.pollingJitterSeconds;
    if (jitter <= 0) {
      return base;
    }
    final delta = _random.nextInt(jitter * 2 + 1) - jitter;
    return math.max(1, base + delta);
  }

  int _nextBoostPollDelaySeconds() {
    final base = AppConstants.boostPollingIntervalSeconds;
    final jitter = AppConstants.boostPollingJitterSeconds;
    if (jitter <= 0) {
      return base;
    }
    final delta = _random.nextInt(jitter * 2 + 1) - jitter;
    return math.max(1, base + delta);
  }

  void _scheduleNextBaselineTick({Duration? overrideDelay}) {
    _pollingTimer?.cancel();
    _pollingTimer = null;

    if (!_baselineActive()) {
      _reconcileBaselineLoop();
      return;
    }

    final delay = overrideDelay ?? Duration(seconds: _nextPollDelaySeconds());
    _pollingTimer = Timer(delay, () {
      if (!ref.mounted) {
        return;
      }
      _requestBaselineRefresh(immediate: true);
    });
  }

  void _scheduleNextBoostTick({Duration? overrideDelay}) {
    _boostPollingTimer?.cancel();
    _boostPollingTimer = null;

    if (!_boostActive()) {
      _reconcileBoostLoop();
      return;
    }

    final delay =
        overrideDelay ?? Duration(seconds: _nextBoostPollDelaySeconds());
    _boostPollingTimer = Timer(delay, () {
      if (!ref.mounted) {
        return;
      }
      _requestBoostRefresh(immediate: true);
    });
  }

  void _requestBaselineRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    if (!_baselineActive()) {
      _reconcileBaselineLoop();
      return;
    }

    _pollingTimer?.cancel();
    _pollingTimer = null;

    final decision = resolveRefreshRequestDecision(
      isInFlight: _isAnyFetchInFlight,
    );
    if (decision.shouldQueuePending) {
      _pendingBaselineRefresh = true;
      _pendingBaselineBypassRateLimit =
          _pendingBaselineBypassRateLimit || bypassRateLimit;
      _recordBaselineSkip('in_flight_queue');
      return;
    }

    if (immediate) {
      unawaited(fetchGroupInstances(bypassRateLimit: bypassRateLimit));
      return;
    }

    _scheduleNextBaselineTick();
  }

  void _requestBoostRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    if (!_boostActive()) {
      _reconcileBoostLoop();
      return;
    }

    _boostPollingTimer?.cancel();
    _boostPollingTimer = null;

    final decision = resolveRefreshRequestDecision(
      isInFlight: _isAnyFetchInFlight,
    );
    if (decision.shouldQueuePending) {
      _pendingBoostRefresh = true;
      _pendingBoostBypassRateLimit =
          _pendingBoostBypassRateLimit || bypassRateLimit;
      return;
    }

    if (immediate) {
      unawaited(fetchBoostedGroupInstances(bypassRateLimit: bypassRateLimit));
      return;
    }

    _scheduleNextBoostTick();
  }

  void _drainPendingRefreshesOrScheduleTicks() {
    if (!ref.mounted || _isAnyFetchInFlight) {
      return;
    }

    if (_pendingBaselineRefresh && _baselineActive()) {
      final bypassRateLimit = _pendingBaselineBypassRateLimit;
      _pendingBaselineRefresh = false;
      _pendingBaselineBypassRateLimit = false;
      unawaited(fetchGroupInstances(bypassRateLimit: bypassRateLimit));
      return;
    }

    if (_pendingBoostRefresh && _boostActive()) {
      final bypassRateLimit = _pendingBoostBypassRateLimit;
      _pendingBoostRefresh = false;
      _pendingBoostBypassRateLimit = false;
      unawaited(fetchBoostedGroupInstances(bypassRateLimit: bypassRateLimit));
      return;
    }

    if (_baselineActive() && _pollingTimer == null) {
      _scheduleNextBaselineTick();
    } else if (!_baselineActive()) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
      _pendingBaselineRefresh = false;
      _pendingBaselineBypassRateLimit = false;
    }

    if (_boostActive() && _boostPollingTimer == null) {
      _scheduleNextBoostTick();
    } else if (!_boostActive()) {
      _boostPollingTimer?.cancel();
      _boostPollingTimer = null;
      _pendingBoostRefresh = false;
      _pendingBoostBypassRateLimit = false;
    }
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

  GroupInstanceWithGroup? _selectInviteTarget(
    List<Instance> instances,
    String groupId,
  ) {
    if (instances.isEmpty) {
      return null;
    }

    Instance? best;
    for (final instance in instances) {
      if (best == null || instance.nUsers > best.nUsers) {
        best = instance;
      }
    }

    if (best == null || best.worldId.isEmpty || best.instanceId.isEmpty) {
      AppLogger.warning(
        'Skipping invite: invalid instance identifiers for group $groupId',
        subCategory: 'group_monitor',
      );
      return null;
    }

    // We intentionally do not gate on canRequestInvite; its meaning for
    // self-invites is unclear, so we attempt and handle failures.
    return GroupInstanceWithGroup(instance: best, groupId: groupId);
  }

  /// Requests a baseline monitoring refresh through the queued single-flight
  /// lifecycle so manual refreshes and automatic triggers share the same flow.
  ///
  /// When [immediate] is true, this starts a refresh now (or marks one as
  /// pending if another fetch is already in-flight). When false, it schedules
  /// the next baseline tick using the normal polling cadence.
  void requestRefresh({bool immediate = true}) {
    _selectionRefreshDebounceTimer?.cancel();
    _selectionRefreshDebounceTimer = null;
    _pendingBaselineRefresh = false;
    _pendingBaselineBypassRateLimit = false;
    _requestBaselineRefresh(immediate: immediate, bypassRateLimit: true);
  }

  void startMonitoring() {
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
  }

  void stopMonitoring() {
    if (!state.isMonitoring) return;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _boostPollingTimer?.cancel();
    _boostPollingTimer = null;
    _selectionRefreshDebounceTimer?.cancel();
    _selectionRefreshDebounceTimer = null;
    _pendingBaselineRefresh = false;
    _pendingBaselineBypassRateLimit = false;
    _pendingBoostRefresh = false;
    _pendingBoostBypassRateLimit = false;
    unawaited(
      _clearBoost(
        persist: true,
        logExpired: false,
        requestBaselineRecovery: false,
      ),
    );
    state = state.copyWith(isMonitoring: false);
    _backoffDelay = 1;

    AppLogger.info('Stopped monitoring', subCategory: 'group_monitor');
  }

  Future<void> fetchGroupInstances({bool bypassRateLimit = false}) async {
    AppLogger.debug(
      'fetchGroupInstances() called',
      subCategory: 'group_monitor',
    );
    final attemptAt = DateTime.now();
    _recordBaselineAttempt(attemptAt);

    if (!_baselineActive()) {
      AppLogger.debug(
        'Skipping instance fetch for inactive baseline loop',
        subCategory: 'group_monitor',
      );
      _recordBaselineSkip('inactive', attemptAt);
      _reconcileBaselineLoop();
      return;
    }

    final decision = resolveRefreshRequestDecision(
      isInFlight: _isAnyFetchInFlight,
    );
    if (decision.shouldQueuePending) {
      _pendingBaselineRefresh = true;
      _pendingBaselineBypassRateLimit =
          _pendingBaselineBypassRateLimit || bypassRateLimit;
      AppLogger.debug(
        'Fetch already in progress, queueing pending baseline refresh',
        subCategory: 'group_monitor',
      );
      _recordBaselineSkip('in_flight_queue', attemptAt);
      return;
    }

    _pollingTimer?.cancel();
    _pollingTimer = null;

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
      return;
    }

    if (!bypassRateLimit) {
      final coordinator = ref.read(apiRateLimitCoordinatorProvider);
      final remaining = coordinator.remainingCooldown(
        ApiRequestLane.groupBaseline,
      );
      if (remaining != null) {
        AppLogger.debug(
          'Baseline poll deferred due to cooldown'
          ' (${remaining.inSeconds}s remaining)',
          subCategory: 'group_monitor',
        );
        ref
            .read(apiCallCounterProvider.notifier)
            .incrementThrottledSkip(lane: ApiRequestLane.groupBaseline);
        _recordBaselineSkip('cooldown', attemptAt);
        _scheduleNextBaselineTick(
          overrideDelay: resolveCooldownAwareDelay(
            remainingCooldown: remaining,
            fallbackDelay: Duration(seconds: _nextPollDelaySeconds()),
          ),
        );
        return;
      }
    }

    _isFetchingBaseline = true;
    try {
      AppLogger.debug(
        'Fetching instances for ${selectedGroupIds.length} groups',
        subCategory: 'group_monitor',
      );

      final api = ref.read(vrchatApiProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final previousGroupInstances = state.groupInstances;
      final previousGroupErrors = state.groupErrors;
      final newInstances = <GroupInstanceWithGroup>[];
      final inviteTargets = <GroupInstanceWithGroup>[];
      final newGroupInstances = <String, List<GroupInstanceWithGroup>>{};
      final newGroupErrors = <String, String>{};
      GroupInstanceWithGroup? newestInstance;
      final excludedGroupIds = selectedGroupIdSet.difference(
        selectedGroupIds.toSet(),
      );
      for (final excludedGroupId in excludedGroupIds) {
        final previousInstances = previousGroupInstances[excludedGroupId] ?? [];
        newGroupInstances[excludedGroupId] = previousInstances;
        for (final previous in previousInstances) {
          newestInstance = _pickNewestInstance(newestInstance, previous);
        }

        final previousError = previousGroupErrors[excludedGroupId];
        if (previousError != null) {
          newGroupErrors[excludedGroupId] = previousError;
        }
      }
      var didInstancesChange = hasGroupInstanceKeyMismatch(
        selectedGroupIds: selectedGroupIdSet,
        groupInstances: previousGroupInstances,
      );

      final responses = await fetchGroupInstancesChunked(
        orderedGroupIds: selectedGroupIds,
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
        return;
      }

      for (final groupResponse in responses) {
        final groupId = groupResponse.groupId;
        final response = groupResponse.response;
        final previousInstances = previousGroupInstances[groupId] ?? [];

        if (response == null) {
          AppLogger.error(
            'Failed to fetch instances for group',
            subCategory: 'group_monitor',
          );
          newGroupErrors[groupId] = 'Failed to fetch instances';
          newGroupInstances[groupId] = previousInstances;
          for (final previous in previousInstances) {
            newestInstance = _pickNewestInstance(newestInstance, previous);
          }
          continue;
        }

        final instances = response.data?.instances ?? [];

        AppLogger.debug(
          'Group returned ${instances.length} instances',
          subCategory: 'group_monitor',
        );

        if (_hasBaseline &&
            state.isMonitoring &&
            state.autoInviteEnabled &&
            previousInstances.isEmpty &&
            instances.isNotEmpty) {
          final target = _selectInviteTarget(instances, groupId);
          if (target != null) {
            inviteTargets.add(target);
          }
        }

        final merged = _mergeFetchedGroupInstancesWithDiff(
          groupId: groupId,
          fetchedInstances: instances,
          previousInstances: previousInstances,
          detectedAt: DateTime.now(),
        );
        newInstances.addAll(merged.newInstances);
        if (merged.didChange) {
          didInstancesChange = true;
        }
        final effectiveInstances = merged.effectiveInstances;
        newGroupInstances[groupId] = effectiveInstances;
        for (final mergedInstance in effectiveInstances) {
          newestInstance = _pickNewestInstance(newestInstance, mergedInstance);
        }
      }

      if (inviteTargets.isNotEmpty) {
        for (final target in inviteTargets) {
          await inviteService.inviteSelfToInstance(target.instance);
        }
      }

      final nextNewestInstanceId = newestInstance?.instance.instanceId;
      final nextGroupInstances = selectGroupInstancesForState(
        didInstancesChange: didInstancesChange,
        previousGroupInstances: previousGroupInstances,
        nextGroupInstances: newGroupInstances,
      );
      final didErrorsChange = !_areStringMapsEquivalent(
        previousGroupErrors,
        newGroupErrors,
      );
      final didNewestChange = state.newestInstanceId != nextNewestInstanceId;
      final totalInstances = nextGroupInstances.values.fold<int>(
        0,
        (sum, instances) => sum + instances.length,
      );

      if (didInstancesChange || didErrorsChange || didNewestChange) {
        state = state.copyWith(
          groupInstances: nextGroupInstances,
          newestInstanceId: nextNewestInstanceId,
          groupErrors: didErrorsChange ? newGroupErrors : previousGroupErrors,
        );
      }

      _hasBaseline = true;
      _recordBaselineSuccess(
        polledGroupCount: selectedGroupIds.length,
        totalInstances: totalInstances,
      );
      // Reset backoff on successful fetch
      _backoffDelay = 1;

      if (newInstances.isNotEmpty) {
        AppLogger.info(
          'Found ${newInstances.length} new instances',
          subCategory: 'group_monitor',
        );
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to fetch group instances',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
      _recordBaselineSkip('error', attemptAt);
      // Exponential backoff: delay before retry, doubling each time
      // Prevents overwhelming the API on transient failures
      await Future.delayed(Duration(seconds: _backoffDelay));
      _backoffDelay = (_backoffDelay * 2).clamp(
        1,
        AppConstants.maxBackoffDelay,
      );
    } finally {
      _isFetchingBaseline = false;
      if (ref.mounted) {
        _drainPendingRefreshesOrScheduleTicks();
      }
    }
  }

  Future<void> fetchBoostedGroupInstances({
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
      _pendingBoostRefresh = true;
      _pendingBoostBypassRateLimit =
          _pendingBoostBypassRateLimit || bypassRateLimit;
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

    _boostPollingTimer?.cancel();
    _boostPollingTimer = null;

    if (!bypassRateLimit) {
      final coordinator = ref.read(apiRateLimitCoordinatorProvider);
      final remaining = coordinator.remainingCooldown(
        ApiRequestLane.groupBoost,
      );
      if (remaining != null) {
        AppLogger.debug(
          'Boost poll deferred due to cooldown'
          ' (${remaining.inSeconds}s remaining)',
          subCategory: 'group_monitor',
        );
        ref
            .read(apiCallCounterProvider.notifier)
            .incrementThrottledSkip(lane: ApiRequestLane.groupBoost);
        _scheduleNextBoostTick(
          overrideDelay: resolveCooldownAwareDelay(
            remainingCooldown: remaining,
            fallbackDelay: Duration(seconds: _nextBoostPollDelaySeconds()),
          ),
        );
        return;
      }
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
      final inviteService = ref.read(inviteServiceProvider);
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

      if (_hasBaseline &&
          state.autoInviteEnabled &&
          previousInstances.isEmpty &&
          instances.isNotEmpty) {
        final target = _selectInviteTarget(instances, groupId);
        if (target != null) {
          await inviteService.inviteSelfToInstance(target.instance);
        }
      }

      final merged = _mergeFetchedGroupInstancesWithDiff(
        groupId: groupId,
        fetchedInstances: instances,
        previousInstances: previousInstances,
        detectedAt: DateTime.now(),
      );
      final newInstances = merged.newInstances;
      final mergedInstances = merged.effectiveInstances;

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
        _drainPendingRefreshesOrScheduleTicks();
      }
    }
  }

  Future<World?> fetchWorldDetails(String worldId) async {
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

  Future<void> clearSelectedGroups() async {
    try {
      await GroupMonitorStorage.clearSelectedGroups();
      await _clearBoost(
        persist: true,
        logExpired: false,
        requestBaselineRecovery: false,
      );

      state = state.copyWith(
        selectedGroupIds: {},
        groupInstances: {},
        newestInstanceId: null,
        boostedGroupId: null,
        boostExpiresAt: null,
        groupErrors: {},
      );
      _reconcileMonitoringForSelectionState();

      AppLogger.debug(
        'Cleared all selected groups from storage',
        subCategory: 'group_monitor',
      );
    } catch (e) {
      AppLogger.error(
        'Failed to clear selected groups',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }
}

final inviteServiceProvider = Provider<InviteService>((ref) {
  final api = ref.read(vrchatApiProvider);
  return InviteService(api);
});

final groupMonitorProvider =
    NotifierProvider.family<GroupMonitorNotifier, GroupMonitorState, String>(
      (arg) => GroupMonitorNotifier(arg),
    );

final groupMonitorSelectedGroupIdsProvider =
    Provider.family<Set<String>, String>((ref, userId) {
      return ref.watch(
        groupMonitorProvider(userId).select((state) => state.selectedGroupIds),
      );
    });

final groupMonitorAllGroupsByIdProvider =
    Provider.family<Map<String, LimitedUserGroups>, String>((ref, userId) {
      final groups = ref.watch(
        groupMonitorProvider(userId).select((state) => state.allGroups),
      );
      final lookup = <String, LimitedUserGroups>{};
      for (final group in groups) {
        final groupId = group.groupId;
        if (groupId != null && groupId.isNotEmpty) {
          lookup[groupId] = group;
        }
      }
      return lookup;
    });

final groupMonitorSelectedGroupsProvider =
    Provider.family<List<LimitedUserGroups>, String>((ref, userId) {
      final selectedGroupIds = ref.watch(
        groupMonitorSelectedGroupIdsProvider(userId),
      );
      final groups = ref.watch(
        groupMonitorProvider(userId).select((state) => state.allGroups),
      );

      return groups
          .where((group) {
            final groupId = group.groupId;
            return groupId != null && selectedGroupIds.contains(groupId);
          })
          .toList(growable: false);
    });

final groupMonitorSortedInstancesProvider =
    Provider.family<List<GroupInstanceWithGroup>, String>((ref, userId) {
      final groupInstances = ref.watch(
        groupMonitorProvider(userId).select((state) => state.groupInstances),
      );
      return sortGroupInstances(
        groupInstances.values.expand((instances) => instances),
      );
    });

final groupMonitorInstanceCountProvider = Provider.family<int, String>((
  ref,
  userId,
) {
  final groupInstances = ref.watch(
    groupMonitorProvider(userId).select((state) => state.groupInstances),
  );
  return groupInstances.values.fold<int>(
    0,
    (sum, instances) => sum + instances.length,
  );
});
