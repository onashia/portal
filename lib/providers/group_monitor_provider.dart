import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_provider.dart';
import '../models/group_instance_with_group.dart';

class GroupMonitorState {
  final List<LimitedUserGroups> allGroups;
  final Set<String> selectedGroupIds;
  final Map<String, List<GroupInstanceWithGroup>> groupInstances;
  final List<GroupInstanceWithGroup> newInstances;
  final bool isMonitoring;
  final bool isLoading;
  final String? errorMessage;
  final Map<String, String> groupErrors;

  GroupMonitorState({
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

class GroupMonitorNotifier extends StateNotifier<GroupMonitorState> {
  final Ref ref;
  final String userId;
  Timer? _pollingTimer;
  int _backoffDelay = 1;
  static const int _maxBackoffDelay = 300;
  static const int _pollingInterval = 60;

  GroupMonitorNotifier(this.ref, this.userId) : super(GroupMonitorState()) {
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

      final api = ref.read(vrchatApiProvider);
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
    final newGroupInstances = Map<String, List<GroupInstanceWithGroup>>.from(
      state.groupInstances,
    );
    final newGroupErrors = Map<String, String>.from(state.groupErrors);

    if (newSelection.contains(groupId)) {
      newSelection.remove(groupId);
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
    developer.log(
      'Toggled group $groupId, now ${newSelection.length} selected',
      name: 'portal.group_monitor',
    );
  }

  void startMonitoring() {
    debugPrint('[MONITOR] startMonitoring() called for userId: $userId');
    developer.log(
      'startMonitoring() called for userId: $userId',
      name: 'portal.group_monitor',
    );

    if (state.isMonitoring) {
      developer.log(
        'Already monitoring, skipping startMonitoring()',
        name: 'portal.group_monitor',
      );
      return;
    }

    state = state.copyWith(isMonitoring: true);
    developer.log(
      'Started monitoring ${state.selectedGroupIds.length} groups',
      name: 'portal.group_monitor',
    );

    try {
      _pollingTimer = Timer.periodic(
        const Duration(seconds: _pollingInterval),
        (_) => fetchGroupInstances(),
      );

      developer.log(
        'Timer created, calling fetchGroupInstances() immediately',
        name: 'portal.group_monitor',
      );

      fetchGroupInstances();
    } catch (e, s) {
      developer.log(
        'Failed to start monitoring',
        name: 'portal.group_monitor',
        error: e,
        stackTrace: s,
      );
    }
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
    debugPrint('[MONITOR] fetchGroupInstances() called');
    debugPrint(
      '[MONITOR] state.selectedGroupIds.length: ${state.selectedGroupIds.length}',
    );
    debugPrint('[MONITOR] state.selectedGroupIds: ${state.selectedGroupIds}');
    developer.log('fetchGroupInstances() called', name: 'portal.group_monitor');

    debugPrint('[MONITOR] About to check if selectedGroupIds is empty');

    if (state.selectedGroupIds.isEmpty) {
      developer.log(
        'No groups selected, skipping instance fetch',
        name: 'portal.group_monitor',
      );
      return;
    }

    try {
      debugPrint('[MONITOR] Entering try block');
      developer.log(
        'Fetching instances for ${state.selectedGroupIds.length} groups',
        name: 'portal.group_monitor',
      );

      final api = ref.read(vrchatApiProvider);
      final newInstances = <GroupInstanceWithGroup>[];
      final newGroupInstances = <String, List<GroupInstanceWithGroup>>{};
      final newGroupErrors = <String, String>{};

      for (final groupId in state.selectedGroupIds) {
        try {
          debugPrint('[MONITOR] Processing groupId: $groupId');
          developer.log(
            'Fetching instances for group: $groupId',
            name: 'portal.group_monitor',
          );

          final response = await api.rawApi
              .getUsersApi()
              .getUserGroupInstancesForGroup(userId: userId, groupId: groupId);

          developer.log(
            'API Response for group $groupId - Status: ${response.statusCode}, Data length: ${response.data?.instances?.length}',
            name: 'portal.group_monitor',
          );

          final instances = response.data?.instances ?? [];

          developer.log(
            'Group $groupId returned ${instances.length} instances',
            name: 'portal.group_monitor',
          );

          if (instances.isNotEmpty) {
            for (final instance in instances) {
              developer.log(
                'Instance - ID: ${instance.instanceId}, Location: ${instance.location}, Members: ${instance.nUsers}, World: ${instance.world.id}',
                name: 'portal.group_monitor',
              );
            }
          }

          final previousInstances = state.groupInstances[groupId] ?? [];
          final previousInstanceIds = previousInstances
              .map((i) => i.instance.instanceId)
              .toSet();

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
        } catch (e, s) {
          final errorMessage = e.toString();
          developer.log(
            'Failed to fetch instances for group $groupId: $errorMessage',
            name: 'portal.group_monitor',
            error: e,
            stackTrace: s,
          );
          newGroupErrors[groupId] = errorMessage;
          newGroupInstances[groupId] = [];
        }
      }

      state = state.copyWith(
        groupInstances: newGroupInstances,
        newInstances: [...state.newInstances, ...newInstances],
        groupErrors: newGroupErrors,
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
      final api = ref.read(vrchatApiProvider);
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
        groupErrors: {},
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
      return GroupMonitorNotifier(ref, userId);
    });
