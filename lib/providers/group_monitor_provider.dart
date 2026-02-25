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
import '../utils/collection_equivalence.dart' as collection_eq;
import 'api_call_counter.dart';
import 'api_rate_limit_provider.dart';
import 'auth_provider.dart';
import 'group_instance_merging.dart';
import 'group_instance_selection.dart';
import 'group_invite_and_boost.dart';
import 'group_monitor_fetching.dart';
import 'group_monitor_state.dart';
import 'group_monitor_storage.dart';
import 'polling_lifecycle.dart';

export 'group_instance_merging.dart';
export 'group_instance_selection.dart';
export 'group_invite_and_boost.dart';
export 'group_monitor_fetching.dart';
export 'group_monitor_state.dart';

part 'group_monitor_provider_fetch.dart';
part 'group_monitor_provider_loops.dart';
part 'group_monitor_provider_persistence.dart';

class GroupMonitorNotifier extends Notifier<GroupMonitorState> {
  GroupMonitorNotifier(this.arg);

  final String arg;

  final _baselineLoop = RefreshLoopState();
  final _boostLoop = RefreshLoopState();
  final _random = math.Random();

  Timer? _selectionRefreshDebounceTimer;
  int _backoffDelay = 1;
  bool _isFetchingBaseline = false;
  bool _isBoostFetching = false;
  bool _isFetchingGroups = false;
  bool _hasBaseline = false;
  DateTime? _boostStartedAt;
  int _boostPollCount = 0;
  bool _boostFirstSeenLogged = false;

  @visibleForTesting
  bool get hasActivePollingTimer => _baselineLoop.hasTimer;

  bool get _isAnyFetchInFlight => _isFetchingBaseline || _isBoostFetching;

  bool _canPollForCurrentSession() {
    final session = ref.read(authSessionSnapshotProvider);
    return isSessionEligible(
      isAuthenticated: session.isAuthenticated,
      authenticatedUserId: session.userId,
      expectedUserId: arg,
    );
  }

  @override
  GroupMonitorState build() {
    _listenForAuthChanges();
    ref.onDispose(() {
      _baselineLoop.reset();
      _boostLoop.reset();
      _selectionRefreshDebounceTimer?.cancel();
      _selectionRefreshDebounceTimer = null;
    });
    _loadSelectedGroups();
    _loadAutoInviteSetting();
    _loadBoostSettings();
    return const GroupMonitorState(isLoading: true);
  }

  void _resetBoostRuntimeTracking({DateTime? startedAt}) {
    _boostStartedAt = startedAt;
    _boostPollCount = 0;
    _boostFirstSeenLogged = false;
  }

  void _applyBoostState({
    required String? groupId,
    required DateTime? expiresAt,
  }) {
    state = state.copyWith(
      boostedGroupId: groupId,
      boostExpiresAt: expiresAt,
      boostPollCount: 0,
      lastBoostLatencyMs: null,
      lastBoostFetchedAt: null,
      boostFirstSeenAfter: null,
    );
  }

  Future<void> toggleAutoInvite() async {
    final newValue = !state.autoInviteEnabled;
    state = state.copyWith(autoInviteEnabled: newValue);
    final didPersist = await _persistStorageWrite(
      actionDescription: 'save auto-invite setting',
      action: () => GroupMonitorStorage.saveAutoInviteEnabled(newValue),
    );
    if (didPersist) {
      AppLogger.info(
        'Auto-invite set to $newValue',
        subCategory: 'group_monitor',
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

    final startedAt = DateTime.now();
    final expiresAt = startedAt.add(
      const Duration(minutes: AppConstants.boostDurationMinutes),
    );
    _resetBoostRuntimeTracking(startedAt: startedAt);
    _applyBoostState(groupId: groupId, expiresAt: expiresAt);
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
      // Clear cached data for deselected group to free memory.
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

  Future<void> fetchUserGroups() => _fetchUserGroupsInternal();

  Future<void> fetchUserGroupsIfNeeded({int minIntervalSeconds = 5}) {
    return _fetchUserGroupsIfNeededInternal(
      minIntervalSeconds: minIntervalSeconds,
    );
  }

  void requestRefresh({bool immediate = true}) {
    _requestRefreshInternal(immediate: immediate);
  }

  void startMonitoring() {
    _startMonitoringInternal();
  }

  void stopMonitoring() {
    _stopMonitoringInternal();
  }

  Future<void> fetchGroupInstances({bool bypassRateLimit = false}) {
    return _fetchGroupInstancesInternal(bypassRateLimit: bypassRateLimit);
  }

  Future<void> fetchBoostedGroupInstances({bool bypassRateLimit = false}) {
    return _fetchBoostedGroupInstancesInternal(
      bypassRateLimit: bypassRateLimit,
    );
  }

  Future<World?> fetchWorldDetails(String worldId) {
    return _fetchWorldDetailsInternal(worldId);
  }

  Future<void> clearSelectedGroups() => _clearSelectedGroupsInternal();
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
