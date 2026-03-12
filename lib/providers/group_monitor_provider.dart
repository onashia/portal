import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/app_constants.dart';
import '../models/group_instance_with_group.dart';
import '../models/relay_hint_message.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../services/auto_invite_service.dart';
import '../services/invite_candidate_resolver.dart';
import '../services/invite_service.dart';
import '../services/relay_hint_service.dart';
import '../utils/app_logger.dart';
import '../utils/collection_equivalence.dart' as collection_eq;
import '../utils/dedupe_tracker.dart';
import 'api_call_counter.dart';
import 'auth_provider.dart';
import 'group_instance_merging.dart';
import 'group_monitor_api.dart';
import 'group_instance_normalization.dart';
import 'group_instance_selection.dart';
import 'group_invite_and_boost.dart';
import 'group_monitor_fetching.dart';
import 'group_monitor_state.dart';
import 'group_monitor_storage.dart';
import 'polling_lifecycle.dart';
import 'refresh_cooldown_handler.dart';
import '../utils/timing_utils.dart';

export 'group_instance_merging.dart';
export 'group_instance_selection.dart';
export 'group_invite_and_boost.dart';
export 'group_monitor_fetching.dart';
export 'group_monitor_state.dart';

part 'group_monitor_provider_fetch.dart';
part 'group_monitor_provider_loops.dart';
part 'group_monitor_provider_persistence.dart';
part 'group_monitor_provider_relay.dart';

class GroupMonitorNotifier extends Notifier<GroupMonitorState> {
  GroupMonitorNotifier(this.arg);

  final String arg;

  final _baselineLoop = RefreshLoopController();
  final _boostLoop = RefreshLoopController();
  final _selectionRefreshDebouncer = RefreshDebouncer();
  int _backoffDelay = 1;
  bool _isFetchingBaseline = false;
  bool _isBoostFetching = false;
  bool _isFetchingGroups = false;
  bool _hasBaseline = false;
  DateTime? _boostStartedAt;
  int _boostPollCount = 0;
  bool _boostFirstSeenLogged = false;
  late InviteService _inviteService;
  late AutoInviteService _autoInviteService;
  late InviteCandidateResolver _inviteCandidateResolver;
  late _GroupMonitorLoopController _loopController;
  late _GroupMonitorRelayController _relayController;
  late _GroupMonitorPersistenceController _persistenceController;

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
    _inviteService = ref.read(inviteServiceProvider);
    _autoInviteService = AutoInviteService(_inviteService);
    _inviteCandidateResolver = InviteCandidateResolver(
      fetchInstance:
          ({
            required String worldId,
            required String instanceId,
            required ApiRequestLane lane,
          }) {
            ref
                .read(apiCallCounterProvider.notifier)
                .incrementApiCall(lane: lane);
            return ref
                .read(groupMonitorApiProvider)
                .getInstance(
                  worldId: worldId,
                  instanceId: instanceId,
                  lane: lane,
                );
          },
    );
    _loopController = _GroupMonitorLoopController(this);
    _relayController = _GroupMonitorRelayController(
      notifier: this,
      service: ref.read(relayHintServiceProvider),
    );
    _persistenceController = _GroupMonitorPersistenceController(this);
    if (AppConstants.relayAssistEnabled && !_relayController.isConfigured) {
      AppLogger.warning(
        'Relay assist is enabled but not configured (missing app secret or bootstrap URL). '
        'Relay will be inactive for this session.',
        subCategory: 'relay',
      );
    }
    // Bind relay streams first because startup load/reconcile work can emit
    // non-replayed status updates.
    _relayController.bindStreams();

    _persistenceController.listenForAuthChanges();
    ref.onDispose(() {
      _baselineLoop.reset();
      _boostLoop.reset();
      _selectionRefreshDebouncer.cancel();
      unawaited(_relayController.dispose());
    });
    _persistenceController.loadSelectedGroups();
    _persistenceController.loadAutoInviteSetting();
    _persistenceController.loadRelayAssistSetting();
    _persistenceController.loadBoostSettings();
    return const GroupMonitorState(
      isLoading: true,
      relayAssistEnabled: AppConstants.relayAssistEnabled,
    );
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
      isBoostActive:
          groupId != null &&
          expiresAt != null &&
          expiresAt.isAfter(DateTime.now()),
      boostedGroupId: groupId,
      boostExpiresAt: expiresAt,
      boostPollCount: 0,
      lastBoostLatencyMs: null,
      lastBoostFetchedAt: null,
      boostFirstSeenAfter: null,
    );
  }

  Future<void> toggleAutoInvite() => _toggleBoolSetting(
    currentValue: state.autoInviteEnabled,
    applyToState: (v) => state.copyWith(autoInviteEnabled: v),
    persist: GroupMonitorStorage.saveAutoInviteEnabled,
    settingName: 'Auto-invite',
    actionDescription: 'save auto-invite setting',
  );

  Future<void> toggleRelayAssist() => _toggleBoolSetting(
    currentValue: state.relayAssistEnabled,
    applyToState: (v) => state.copyWith(relayAssistEnabled: v),
    persist: GroupMonitorStorage.saveRelayAssistEnabled,
    settingName: 'Relay assist',
    actionDescription: 'save relay assist setting',
  );

  Future<void> _toggleBoolSetting({
    required bool currentValue,
    required GroupMonitorState Function(bool) applyToState,
    required Future<void> Function(bool) persist,
    required String settingName,
    required String actionDescription,
  }) async {
    final newValue = !currentValue;
    state = applyToState(newValue);
    final didPersist = await _persistenceController.persistStorageWrite(
      actionDescription: actionDescription,
      action: () => persist(newValue),
    );
    if (didPersist) {
      AppLogger.info(
        '$settingName set to $newValue',
        subCategory: 'group_monitor',
      );
    }
    _relayController.reconcileConnection();
  }

  Future<void> setBoostedGroup(String? groupId) async {
    if (groupId == null || groupId.isEmpty) {
      await _persistenceController.clearBoost(persist: true, logExpired: false);
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
      await _persistenceController.clearBoost(persist: true, logExpired: false);
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
    await _persistenceController.persistBoostSettings(
      groupId: groupId,
      boostExpiresAt: expiresAt,
    );
    AppLogger.info(
      'Boosted group set to $groupId',
      subCategory: 'group_monitor',
    );

    if (state.isMonitoring) {
      _loopController.requestBoostRefresh(immediate: true);
    }
    _relayController.reconcileConnection();
  }

  Future<void> clearBoost() async {
    await _persistenceController.clearBoost(persist: true, logExpired: false);
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
        unawaited(
          _persistenceController.clearBoost(persist: true, logExpired: false),
        );
      }
    } else {
      newSelection.add(groupId);
    }

    state = state.copyWith(
      selectedGroupIds: newSelection,
      groupInstances: newGroupInstances,
      groupErrors: newGroupErrors,
    );
    _loopController.reconcileMonitoringForSelectionState();
    if (!wasSelected && wasMonitoring && state.isMonitoring) {
      _loopController.scheduleSelectionTriggeredBaselineRefresh();
    }
    _persistenceController.saveSelectedGroups();
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
    _loopController.requestRefresh(immediate: immediate);
  }

  void startMonitoring() {
    _loopController.startMonitoring();
  }

  void stopMonitoring() {
    _loopController.stopMonitoring();
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

  Future<void> clearSelectedGroups() =>
      _persistenceController.clearSelectedGroupsInternal();
}

final inviteServiceProvider = Provider<InviteService>((ref) {
  final api = ref.read(vrchatApiProvider);
  return InviteService(api);
});

final relayHintServiceProvider = Provider<RelayHintService>((ref) {
  final service = RelayHintService();
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
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
