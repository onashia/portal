import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../models/group_instance_with_group.dart';
import '../services/invite_service.dart';
import 'api_call_counter.dart';
import 'auth_provider.dart';
import 'group_monitor_state.dart';
import 'group_monitor_storage.dart';

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

  @override
  GroupMonitorState build() {
    _loadSelectedGroups();
    _loadAutoInviteSetting();
    _loadBoostSettings();
    return const GroupMonitorState(isLoading: true);
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
          _scheduleNextBoostPoll(immediate: true);
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
      state = state.copyWith(selectedGroupIds: selectedIds.toSet());
      AppLogger.debug(
        'Loaded ${selectedIds.length} selected groups from storage',
        subCategory: 'group_monitor',
      );
      if (selectedIds.isNotEmpty && !state.isMonitoring) {
        startMonitoring();
      }
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
    state = state.copyWith(boostedGroupId: groupId, boostExpiresAt: expiresAt);
    state = state.copyWith(
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
      _scheduleNextBoostPoll(immediate: true);
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
  }) async {
    _boostPollingTimer?.cancel();
    _boostPollingTimer = null;
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
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      AppLogger.debug('Fetching groups for user', subCategory: 'group_monitor');

      ref.read(apiCallCounterProvider.notifier).incrementApiCall();

      final api = ref.read(vrchatApiProvider);
      final response = await api.rawApi.getUsersApi().getUserGroups(
        userId: arg,
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
    }
  }

  Future<void> fetchUserGroupsIfNeeded({int minIntervalSeconds = 5}) async {
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
    final newSelection = Set<String>.from(state.selectedGroupIds);
    final newGroupInstances = Map<String, List<GroupInstanceWithGroup>>.from(
      state.groupInstances,
    );
    final newGroupErrors = Map<String, String>.from(state.groupErrors);

    if (newSelection.contains(groupId)) {
      newSelection.remove(groupId);
      // Clear cached data for deselected group to free memory
      newGroupInstances.remove(groupId);
      newGroupErrors.remove(groupId);
      if (state.boostedGroupId == groupId) {
        unawaited(_clearBoost(persist: true, logExpired: false));
      }
      if (newSelection.isEmpty && state.isMonitoring) {
        stopMonitoring();
      }
    } else {
      newSelection.add(groupId);
      if (newSelection.length == 1 && !state.isMonitoring) {
        startMonitoring();
      }
    }

    state = state.copyWith(
      selectedGroupIds: newSelection,
      groupInstances: newGroupInstances,
      groupErrors: newGroupErrors,
    );
    _saveSelectedGroups();
    AppLogger.debug(
      'Toggled group, now ${newSelection.length} selected',
      subCategory: 'group_monitor',
    );
  }

  Timer? _pollingTimer;
  Timer? _boostPollingTimer;
  int _backoffDelay = 1;
  bool _isFetching = false;
  bool _hasBaseline = false;
  DateTime? _boostStartedAt;
  int _boostPollCount = 0;
  bool _boostFirstSeenLogged = false;
  final _random = math.Random();

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

  void _scheduleNextBoostPoll({bool immediate = false}) {
    _boostPollingTimer?.cancel();

    if (!state.isMonitoring || !state.isBoostActive) {
      return;
    }

    final delaySeconds = immediate ? 0 : _nextBoostPollDelaySeconds();
    _boostPollingTimer = Timer(Duration(seconds: delaySeconds), () async {
      await fetchBoostedGroupInstances();
      _scheduleNextBoostPoll();
    });
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

  void _scheduleNextPoll({bool immediate = false}) {
    _pollingTimer?.cancel();

    if (!state.isMonitoring) {
      return;
    }

    final delaySeconds = immediate ? 0 : _nextPollDelaySeconds();
    _pollingTimer = Timer(Duration(seconds: delaySeconds), () async {
      await fetchGroupInstances();
      _scheduleNextPoll();
    });
  }

  void startMonitoring() {
    AppLogger.info('Starting monitoring', subCategory: 'group_monitor');

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

    try {
      // Initial fetch to populate data immediately
      _scheduleNextPoll(immediate: true);
      if (state.isBoostActive) {
        _scheduleNextBoostPoll(immediate: true);
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to start monitoring',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
      state = state.copyWith(isMonitoring: false);
    }
  }

  void stopMonitoring() {
    if (!state.isMonitoring) return;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _boostPollingTimer?.cancel();
    _boostPollingTimer = null;
    unawaited(_clearBoost(persist: true, logExpired: false));
    state = state.copyWith(isMonitoring: false);
    _backoffDelay = 1;

    AppLogger.info('Stopped monitoring', subCategory: 'group_monitor');
  }

  Future<void> fetchGroupInstances() async {
    AppLogger.debug(
      'fetchGroupInstances() called',
      subCategory: 'group_monitor',
    );

    if (_isFetching) {
      AppLogger.debug(
        'Fetch already in progress, skipping',
        subCategory: 'group_monitor',
      );
      return;
    }

    final selectedGroupIds = state.selectedGroupIds.toList(growable: false);
    if (selectedGroupIds.isEmpty) {
      AppLogger.warning(
        'No groups selected, skipping instance fetch',
        subCategory: 'group_monitor',
      );
      return;
    }

    _isFetching = true;
    try {
      AppLogger.debug(
        'Fetching instances for ${selectedGroupIds.length} groups',
        subCategory: 'group_monitor',
      );

      final api = ref.read(vrchatApiProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final previousGroupInstances = state.groupInstances;
      final newInstances = <GroupInstanceWithGroup>[];
      final inviteTargets = <GroupInstanceWithGroup>[];
      final newGroupInstances = <String, List<GroupInstanceWithGroup>>{};
      final newGroupErrors = <String, String>{};
      GroupInstanceWithGroup? newestInstance;

      final futures = selectedGroupIds.map((groupId) async {
        ref.read(apiCallCounterProvider.notifier).incrementApiCall();
        try {
          return await api.rawApi.getUsersApi().getUserGroupInstancesForGroup(
            userId: arg,
            groupId: groupId,
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
      }).toList();

      final responses = await Future.wait(futures);

      for (int i = 0; i < responses.length; i++) {
        final groupId = selectedGroupIds[i];
        final response = responses[i];
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

        final merged = mergeFetchedGroupInstances(
          groupId: groupId,
          fetchedInstances: instances,
          previousInstances: previousInstances,
          detectedAt: DateTime.now(),
        );
        newInstances.addAll(merged.newInstances);
        newGroupInstances[groupId] = merged.mergedInstances;
        for (final mergedInstance in merged.mergedInstances) {
          newestInstance = _pickNewestInstance(newestInstance, mergedInstance);
        }
      }

      if (inviteTargets.isNotEmpty) {
        for (final target in inviteTargets) {
          await inviteService.inviteSelfToInstance(target.instance);
        }
      }

      state = state.copyWith(
        groupInstances: newGroupInstances,
        newestInstanceId: newestInstance?.instance.instanceId,
        groupErrors: newGroupErrors,
      );

      _hasBaseline = true;
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
      // Exponential backoff: delay before retry, doubling each time
      // Prevents overwhelming the API on transient failures
      await Future.delayed(Duration(seconds: _backoffDelay));
      _backoffDelay = (_backoffDelay * 2).clamp(
        1,
        AppConstants.maxBackoffDelay,
      );
    } finally {
      _isFetching = false;
    }
  }

  Future<void> fetchBoostedGroupInstances() async {
    if (!state.isMonitoring) {
      return;
    }

    final isActive = await _ensureBoostActive();
    if (!isActive) {
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

    if (_isFetching) {
      AppLogger.debug(
        'Fetch already in progress, skipping boosted poll',
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

    _isFetching = true;
    try {
      _boostPollCount += 1;
      final pollStart = DateTime.now();
      AppLogger.debug(
        'Boost poll #$_boostPollCount started for $groupId',
        subCategory: 'group_monitor',
      );

      ref.read(apiCallCounterProvider.notifier).incrementApiCall();
      final api = ref.read(vrchatApiProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final response = await api.rawApi
          .getUsersApi()
          .getUserGroupInstancesForGroup(userId: arg, groupId: groupId);

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
        state = state.copyWith(boostFirstSeenAfter: delta);
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

      final merged = mergeFetchedGroupInstances(
        groupId: groupId,
        fetchedInstances: instances,
        previousInstances: previousInstances,
        detectedAt: DateTime.now(),
      );
      final newInstances = merged.newInstances;

      final updatedGroupInstances =
          Map<String, List<GroupInstanceWithGroup>>.from(state.groupInstances);
      updatedGroupInstances[groupId] = merged.mergedInstances;

      final updatedGroupErrors = Map<String, String>.from(state.groupErrors);
      updatedGroupErrors.remove(groupId);

      state = state.copyWith(
        groupInstances: updatedGroupInstances,
        newestInstanceId: newestInstanceIdFromGroupInstances(
          updatedGroupInstances,
        ),
        groupErrors: updatedGroupErrors,
        boostPollCount: _boostPollCount,
        lastBoostLatencyMs: latencyMs,
        lastBoostFetchedAt: fetchedAt,
      );

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
      final updatedGroupErrors = Map<String, String>.from(state.groupErrors);
      updatedGroupErrors[groupId] = 'Failed to fetch instances';
      state = state.copyWith(groupErrors: updatedGroupErrors);
    } finally {
      _isFetching = false;
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
      await _clearBoost(persist: true, logExpired: false);

      state = state.copyWith(
        selectedGroupIds: {},
        groupInstances: {},
        newestInstanceId: null,
        boostedGroupId: null,
        boostExpiresAt: null,
        groupErrors: {},
      );

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
