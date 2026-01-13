import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_provider.dart';

class GroupMonitorState {
  final List<LimitedUserGroups> allGroups;
  final Set<String> selectedGroupIds;
  final Map<String, List<GroupInstance>> groupInstances;
  final List<GroupInstance> newInstances;
  final bool isMonitoring;
  final bool isLoading;
  final String? errorMessage;

  GroupMonitorState({
    this.allGroups = const [],
    this.selectedGroupIds = const {},
    this.groupInstances = const {},
    this.newInstances = const [],
    this.isMonitoring = false,
    this.isLoading = false,
    this.errorMessage,
  });

  GroupMonitorState copyWith({
    List<LimitedUserGroups>? allGroups,
    Set<String>? selectedGroupIds,
    Map<String, List<GroupInstance>>? groupInstances,
    List<GroupInstance>? newInstances,
    bool? isMonitoring,
    bool? isLoading,
    String? errorMessage,
  }) {
    return GroupMonitorState(
      allGroups: allGroups ?? this.allGroups,
      selectedGroupIds: selectedGroupIds ?? this.selectedGroupIds,
      groupInstances: groupInstances ?? this.groupInstances,
      newInstances: newInstances ?? this.newInstances,
      isMonitoring: isMonitoring ?? this.isMonitoring,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class GroupMonitorNotifier extends StateNotifier<GroupMonitorState> {
  final VrchatDart api;
  final String userId;
  Timer? _pollingTimer;
  int _backoffDelay = 1;
  static const int _maxBackoffDelay = 300;
  static const int _pollingInterval = 60;

  GroupMonitorNotifier(this.api, this.userId) : super(GroupMonitorState()) {
    _loadSelectedGroups();
  }

  Future<void> _loadSelectedGroups() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedIds = prefs.getStringList('selectedGroupIds') ?? [];
      state = state.copyWith(selectedGroupIds: selectedIds.toSet());
      developer.log(
        'Loaded ${selectedIds.length} selected groups from storage',
        name: 'portal.group_monitor',
      );
    } catch (e) {
      developer.log(
        'Failed to load selected groups',
        name: 'portal.group_monitor',
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
      developer.log(
        'Failed to save selected groups',
        name: 'portal.group_monitor',
        error: e,
      );
    }
  }

  Future<void> fetchUserGroups() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      developer.log(
        'Fetching groups for user: $userId',
        name: 'portal.group_monitor',
      );

      final response = await api.rawApi.getUsersApi().getUserGroups(
        userId: userId,
      );
      final groups = response.data ?? [];

      developer.log(
        'Fetched ${groups.length} groups',
        name: 'portal.group_monitor',
      );

      state = state.copyWith(allGroups: groups, isLoading: false);
    } catch (e, s) {
      developer.log(
        'Failed to fetch user groups',
        name: 'portal.group_monitor',
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
    final newGroupInstances = Map<String, List<GroupInstance>>.from(
      state.groupInstances,
    );

    if (newSelection.contains(groupId)) {
      newSelection.remove(groupId);
      newGroupInstances.remove(groupId);
    } else {
      newSelection.add(groupId);
    }

    state = state.copyWith(
      selectedGroupIds: newSelection,
      groupInstances: newGroupInstances,
    );

    _saveSelectedGroups();
    developer.log(
      'Toggled group $groupId, now ${newSelection.length} selected',
      name: 'portal.group_monitor',
    );
  }

  void startMonitoring() {
    if (state.isMonitoring) return;

    state = state.copyWith(isMonitoring: true);
    developer.log(
      'Started monitoring ${state.selectedGroupIds.length} groups',
      name: 'portal.group_monitor',
    );

    _pollingTimer = Timer.periodic(
      const Duration(seconds: _pollingInterval),
      (_) => fetchGroupInstances(),
    );

    fetchGroupInstances();
  }

  void stopMonitoring() {
    if (!state.isMonitoring) return;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    state = state.copyWith(isMonitoring: false);
    _backoffDelay = 1;

    developer.log('Stopped monitoring', name: 'portal.group_monitor');
  }

  Future<void> fetchGroupInstances() async {
    if (state.selectedGroupIds.isEmpty) {
      developer.log(
        'No groups selected, skipping instance fetch',
        name: 'portal.group_monitor',
      );
      return;
    }

    try {
      developer.log(
        'Fetching instances for ${state.selectedGroupIds.length} groups',
        name: 'portal.group_monitor',
      );

      final newInstances = <GroupInstance>[];
      final newGroupInstances = <String, List<GroupInstance>>{};

      for (final groupId in state.selectedGroupIds) {
        try {
          final response = await api.rawApi.getGroupsApi().getGroupInstances(
            groupId: groupId,
          );
          final instances = response.data ?? [];

          final previousInstances = state.groupInstances[groupId] ?? [];
          final previousInstanceIds = previousInstances
              .map((i) => i.instanceId)
              .toSet();

          for (final instance in instances) {
            if (!previousInstanceIds.contains(instance.instanceId)) {
              newInstances.add(instance);
            }
          }

          newGroupInstances[groupId] = instances;
        } catch (e, s) {
          developer.log(
            'Failed to fetch instances for group $groupId',
            name: 'portal.group_monitor',
            error: e,
            stackTrace: s,
          );
        }
      }

      state = state.copyWith(
        groupInstances: newGroupInstances,
        newInstances: [...state.newInstances, ...newInstances],
      );

      _backoffDelay = 1;

      if (newInstances.isNotEmpty) {
        developer.log(
          'Found ${newInstances.length} new instances',
          name: 'portal.group_monitor',
        );
      }
    } catch (e, s) {
      developer.log(
        'Failed to fetch group instances',
        name: 'portal.group_monitor',
        error: e,
        stackTrace: s,
      );

      await Future.delayed(Duration(seconds: _backoffDelay));
      _backoffDelay = (_backoffDelay * 2).clamp(1, _maxBackoffDelay);
    }
  }

  Future<World?> fetchWorldDetails(String worldId) async {
    try {
      final response = await api.rawApi.getWorldsApi().getWorld(
        worldId: worldId,
      );
      return response.data;
    } catch (e, s) {
      developer.log(
        'Failed to fetch world details for $worldId',
        name: 'portal.group_monitor',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

  void acknowledgeNewInstances() {
    state = state.copyWith(newInstances: []);
    developer.log(
      'Acknowledged all new instances',
      name: 'portal.group_monitor',
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
      );

      developer.log(
        'Cleared all selected groups from storage',
        name: 'portal.group_monitor',
      );
    } catch (e) {
      developer.log(
        'Failed to clear selected groups',
        name: 'portal.group_monitor',
        error: e,
      );
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

final groupMonitorProvider =
    StateNotifierProvider.family<
      GroupMonitorNotifier,
      GroupMonitorState,
      String
    >((ref, userId) {
      final api = ref.watch(vrchatApiProvider);
      return GroupMonitorNotifier(api, userId);
    });
