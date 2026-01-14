import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import '../models/group_instance_with_group.dart';
import 'api_call_counter.dart';
import 'auth_provider.dart';

class GroupMonitorState {
  final List<LimitedUserGroups> allGroups;
  final Set<String> selectedGroupIds;
  final Map<String, List<GroupInstanceWithGroup>> groupInstances;
  final List<GroupInstanceWithGroup> newInstances;
  final bool isMonitoring;
  final bool isLoading;
  final String? errorMessage;
  final Map<String, String> groupErrors;

  const GroupMonitorState({
    this.allGroups = const [],
    this.selectedGroupIds = const {},
    this.groupInstances = const {},
    this.newInstances = const [],
    this.isMonitoring = false,
    this.isLoading = false,
    this.errorMessage,
    this.groupErrors = const {},
  });

  GroupMonitorState copyWith({
    List<LimitedUserGroups>? allGroups,
    Set<String>? selectedGroupIds,
    Map<String, List<GroupInstanceWithGroup>>? groupInstances,
    List<GroupInstanceWithGroup>? newInstances,
    bool? isMonitoring,
    bool? isLoading,
    String? errorMessage,
    Map<String, String>? groupErrors,
  }) {
    return GroupMonitorState(
      allGroups: allGroups ?? this.allGroups,
      selectedGroupIds: selectedGroupIds ?? this.selectedGroupIds,
      groupInstances: groupInstances ?? this.groupInstances,
      newInstances: newInstances ?? this.newInstances,
      isMonitoring: isMonitoring ?? this.isMonitoring,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      groupErrors: groupErrors ?? this.groupErrors,
    );
  }
}

class GroupMonitorNotifier extends Notifier<GroupMonitorState> {
  final String userId;

  GroupMonitorNotifier(this.userId);

  @override
  GroupMonitorState build() {
    _loadSelectedGroups();
    return GroupMonitorState();
  }

  Future<void> _loadSelectedGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedIds = prefs.getStringList('selectedGroupIds') ?? [];
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

  Future<void> _saveSelectedGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'selectedGroupIds',
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
        userId: userId,
      );
      final groups = response.data ?? [];

      AppLogger.info(
        'Fetched ${groups.length} groups',
        subCategory: 'group_monitor',
      );

      state = state.copyWith(allGroups: groups, isLoading: false);
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
  int _backoffDelay = 1;

  void startMonitoring() {
    AppLogger.info('Starting monitoring', subCategory: 'group_monitor');

    if (state.isMonitoring) {
      AppLogger.warning(
        'Already monitoring, skipping start',
        subCategory: 'group_monitor',
      );
      return;
    }

    state = state.copyWith(isMonitoring: true);
    AppLogger.info(
      'Started monitoring ${state.selectedGroupIds.length} groups',
      subCategory: 'group_monitor',
    );

    try {
      _pollingTimer = Timer.periodic(
        Duration(seconds: AppConstants.pollingIntervalSeconds),
        (_) => fetchGroupInstances(),
      );

      // Initial fetch to populate data immediately
      fetchGroupInstances();
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
    state = state.copyWith(isMonitoring: false);
    _backoffDelay = 1;

    AppLogger.info('Stopped monitoring', subCategory: 'group_monitor');
  }

  Future<void> fetchGroupInstances() async {
    AppLogger.debug(
      'fetchGroupInstances() called',
      subCategory: 'group_monitor',
    );

    if (state.selectedGroupIds.isEmpty) {
      AppLogger.warning(
        'No groups selected, skipping instance fetch',
        subCategory: 'group_monitor',
      );
      return;
    }

    try {
      AppLogger.debug(
        'Fetching instances for ${state.selectedGroupIds.length} groups',
        subCategory: 'group_monitor',
      );

      final api = ref.read(vrchatApiProvider);
      final newInstances = <GroupInstanceWithGroup>[];
      final newGroupInstances = <String, List<GroupInstanceWithGroup>>{};
      final newGroupErrors = <String, String>{};

      final futures = state.selectedGroupIds.map((groupId) async {
        ref.read(apiCallCounterProvider.notifier).incrementApiCall();
        try {
          return await api.rawApi.getUsersApi().getUserGroupInstancesForGroup(
            userId: userId,
            groupId: groupId,
          );
        } catch (e) {
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

      state = state.copyWith(
        groupInstances: newGroupInstances,
        // Accumulate new instances across all polls until acknowledged
        newInstances: [...state.newInstances, ...newInstances],
        groupErrors: newGroupErrors,
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
      // Exponential backoff: delay before retry, doubling each time
      // Prevents overwhelming the API on transient failures
      await Future.delayed(Duration(seconds: _backoffDelay));
      _backoffDelay = (_backoffDelay * 2).clamp(
        1,
        AppConstants.maxBackoffDelay,
      );
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
      await prefs.remove('selectedGroupIds');

      state = state.copyWith(
        selectedGroupIds: {},
        groupInstances: {},
        newInstances: [],
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

final groupMonitorProvider =
    NotifierProvider.family<GroupMonitorNotifier, GroupMonitorState, String>(
      (userId) => GroupMonitorNotifier(userId),
    );
