import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../constants/storage_keys.dart';
import '../utils/app_logger.dart';
import '../models/group_instance_with_group.dart';
import '../services/invite_service.dart';
import 'api_call_counter.dart';
import 'auth_provider.dart';

@immutable
class GroupMonitorState {
  final List<LimitedUserGroups> allGroups;
  final Set<String> selectedGroupIds;
  final Map<String, List<GroupInstanceWithGroup>> groupInstances;
  final List<GroupInstanceWithGroup> newInstances;
  final bool autoInviteEnabled;
  final String? boostedGroupId;
  final DateTime? boostExpiresAt;
  final int boostPollCount;
  final int? lastBoostLatencyMs;
  final DateTime? lastBoostFetchedAt;
  final Duration? boostFirstSeenAfter;
  final bool isMonitoring;
  final bool isLoading;
  final String? errorMessage;
  final Map<String, String> groupErrors;
  final DateTime? lastGroupsFetchTime;

  const GroupMonitorState({
    this.allGroups = const [],
    this.selectedGroupIds = const {},
    this.groupInstances = const {},
    this.newInstances = const [],
    this.autoInviteEnabled = true,
    this.boostedGroupId,
    this.boostExpiresAt,
    this.boostPollCount = 0,
    this.lastBoostLatencyMs,
    this.lastBoostFetchedAt,
    this.boostFirstSeenAfter,
    this.isMonitoring = false,
    this.isLoading = false,
    this.errorMessage,
    this.groupErrors = const {},
    this.lastGroupsFetchTime,
  });

  GroupMonitorState copyWith({
    List<LimitedUserGroups>? allGroups,
    Set<String>? selectedGroupIds,
    Map<String, List<GroupInstanceWithGroup>>? groupInstances,
    List<GroupInstanceWithGroup>? newInstances,
    bool? autoInviteEnabled,
    String? boostedGroupId,
    DateTime? boostExpiresAt,
    int? boostPollCount,
    int? lastBoostLatencyMs,
    DateTime? lastBoostFetchedAt,
    Duration? boostFirstSeenAfter,
    bool? isMonitoring,
    bool? isLoading,
    String? errorMessage,
    Map<String, String>? groupErrors,
    DateTime? lastGroupsFetchTime,
  }) {
    return GroupMonitorState(
      allGroups: allGroups ?? this.allGroups,
      selectedGroupIds: selectedGroupIds ?? this.selectedGroupIds,
      groupInstances: groupInstances ?? this.groupInstances,
      newInstances: newInstances ?? this.newInstances,
      autoInviteEnabled: autoInviteEnabled ?? this.autoInviteEnabled,
      boostedGroupId: boostedGroupId ?? this.boostedGroupId,
      boostExpiresAt: boostExpiresAt ?? this.boostExpiresAt,
      boostPollCount: boostPollCount ?? this.boostPollCount,
      lastBoostLatencyMs: lastBoostLatencyMs ?? this.lastBoostLatencyMs,
      lastBoostFetchedAt: lastBoostFetchedAt ?? this.lastBoostFetchedAt,
      boostFirstSeenAfter: boostFirstSeenAfter ?? this.boostFirstSeenAfter,
      isMonitoring: isMonitoring ?? this.isMonitoring,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      groupErrors: groupErrors ?? this.groupErrors,
      lastGroupsFetchTime: lastGroupsFetchTime ?? this.lastGroupsFetchTime,
    );
  }

  bool get isBoostActive =>
      boostedGroupId != null &&
      boostExpiresAt != null &&
      boostExpiresAt!.isAfter(DateTime.now());
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
      final prefs = await SharedPreferences.getInstance();
      final boostedGroupId = prefs.getString(StorageKeys.boostedGroupId);
      final expiresAtRaw = prefs.getString(StorageKeys.boostExpiresAt);
      final boostExpiresAt = expiresAtRaw == null
          ? null
          : DateTime.tryParse(expiresAtRaw);

      if (boostedGroupId != null &&
          boostExpiresAt != null &&
          boostExpiresAt.isAfter(DateTime.now())) {
        state = state.copyWith(
          boostedGroupId: boostedGroupId,
          boostExpiresAt: boostExpiresAt,
          boostPollCount: 0,
          lastBoostLatencyMs: null,
          lastBoostFetchedAt: null,
          boostFirstSeenAfter: null,
        );
        _boostStartedAt = boostExpiresAt.subtract(
          const Duration(minutes: AppConstants.boostDurationMinutes),
        );
        _boostPollCount = 0;
        _boostFirstSeenLogged = false;
        AppLogger.debug(
          'Loaded boosted group: $boostedGroupId',
          subCategory: 'group_monitor',
        );
      } else if (boostedGroupId != null || boostExpiresAt != null) {
        await _clearBoost(persist: true, logExpired: true);
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
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(StorageKeys.autoInviteEnabled) ?? true;
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
      final prefs = await SharedPreferences.getInstance();
      final selectedIds =
          prefs.getStringList(StorageKeys.selectedGroupIds) ?? [];
      state = state.copyWith(selectedGroupIds: selectedIds.toSet());
      AppLogger.debug(
        'Loaded ${selectedIds.length} selected groups from storage',
        subCategory: 'group_monitor',
      );
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(StorageKeys.autoInviteEnabled, newValue);
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
      final prefs = await SharedPreferences.getInstance();
      if (groupId == null || boostExpiresAt == null) {
        await prefs.remove(StorageKeys.boostedGroupId);
        await prefs.remove(StorageKeys.boostExpiresAt);
      } else {
        await prefs.setString(StorageKeys.boostedGroupId, groupId);
        await prefs.setString(
          StorageKeys.boostExpiresAt,
          boostExpiresAt.toIso8601String(),
        );
      }
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        StorageKeys.selectedGroupIds,
        state.selectedGroupIds.toList(),
      );
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
    } else {
      newSelection.add(groupId);
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

    if (state.selectedGroupIds.isEmpty) {
      AppLogger.warning(
        'No groups selected, skipping instance fetch',
        subCategory: 'group_monitor',
      );
      return;
    }

    _isFetching = true;
    try {
      AppLogger.debug(
        'Fetching instances for ${state.selectedGroupIds.length} groups',
        subCategory: 'group_monitor',
      );

      final api = ref.read(vrchatApiProvider);
      final inviteService = ref.read(inviteServiceProvider);
      final newInstances = <GroupInstanceWithGroup>[];
      final inviteTargets = <GroupInstanceWithGroup>[];
      final newGroupInstances = <String, List<GroupInstanceWithGroup>>{};
      final newGroupErrors = <String, String>{};

      final futures = state.selectedGroupIds.map((groupId) async {
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
        final groupId = state.selectedGroupIds.elementAt(i);
        final response = responses[i];

        if (response == null) {
          AppLogger.error(
            'Failed to fetch instances for group',
            subCategory: 'group_monitor',
          );
          newGroupErrors[groupId] = 'Failed to fetch instances';
          newGroupInstances[groupId] = state.groupInstances[groupId] ?? [];
          continue;
        }

        final instances = response.data?.instances ?? [];

        AppLogger.debug(
          'Group returned ${instances.length} instances',
          subCategory: 'group_monitor',
        );

        // Compare with previous fetch to identify new instances
        final previousInstances = state.groupInstances[groupId] ?? [];
        final previousInstanceIds = previousInstances
            .map((i) => i.instance.instanceId)
            .toSet();

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

        // Track instances that weren't in previous fetch
        for (final instance in instances) {
          final instanceWithGroup = GroupInstanceWithGroup(
            instance: instance,
            groupId: groupId,
          );
          if (!previousInstanceIds.contains(instance.instanceId)) {
            newInstances.add(instanceWithGroup);
          }
        }

        newGroupInstances[groupId] = instances
            .map((i) => GroupInstanceWithGroup(instance: i, groupId: groupId))
            .toList();
      }

      if (inviteTargets.isNotEmpty) {
        for (final target in inviteTargets) {
          await inviteService.inviteSelfToInstance(target.instance);
        }
      }

      state = state.copyWith(
        groupInstances: newGroupInstances,
        // Accumulate new instances across all polls until acknowledged
        newInstances: [...state.newInstances, ...newInstances],
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
      final previousInstanceIds = previousInstances
          .map((i) => i.instance.instanceId)
          .toSet();

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

      final newInstances = <GroupInstanceWithGroup>[];
      for (final instance in instances) {
        final instanceWithGroup = GroupInstanceWithGroup(
          instance: instance,
          groupId: groupId,
        );
        if (!previousInstanceIds.contains(instance.instanceId)) {
          newInstances.add(instanceWithGroup);
        }
      }

      final updatedGroupInstances =
          Map<String, List<GroupInstanceWithGroup>>.from(state.groupInstances);
      updatedGroupInstances[groupId] = instances
          .map((i) => GroupInstanceWithGroup(instance: i, groupId: groupId))
          .toList();

      final updatedGroupErrors = Map<String, String>.from(state.groupErrors);
      updatedGroupErrors.remove(groupId);

      state = state.copyWith(
        groupInstances: updatedGroupInstances,
        newInstances: [...state.newInstances, ...newInstances],
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

  void acknowledgeNewInstances() {
    state = state.copyWith(newInstances: []);
    AppLogger.debug(
      'Acknowledged all new instances',
      subCategory: 'group_monitor',
    );
  }

  Future<void> clearSelectedGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.selectedGroupIds);
      await _clearBoost(persist: true, logExpired: false);

      state = state.copyWith(
        selectedGroupIds: {},
        groupInstances: {},
        newInstances: [],
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
