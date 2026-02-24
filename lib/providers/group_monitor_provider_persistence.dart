// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'group_monitor_provider.dart';

extension GroupMonitorPersistenceExtension on GroupMonitorNotifier {
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

  Future<void> _clearBoost({
    required bool persist,
    required bool logExpired,
    bool requestBaselineRecovery = true,
  }) async {
    final hadBoost =
        state.boostedGroupId != null || state.boostExpiresAt != null;
    _boostLoop.cancelTimer();
    _boostLoop.pendingRefresh = false;
    _resetBoostRuntimeTracking();
    _applyBoostState(groupId: null, expiresAt: null);

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
    await _persistStorageWrite(
      actionDescription: 'persist boost settings',
      action: () => GroupMonitorStorage.saveBoostSettings(
        groupId: groupId,
        boostExpiresAt: boostExpiresAt,
      ),
    );
  }

  Future<void> _saveSelectedGroups() async {
    await _persistStorageWrite(
      actionDescription: 'save selected groups',
      action: () =>
          GroupMonitorStorage.saveSelectedGroupIds(state.selectedGroupIds),
    );
  }

  Future<bool> _persistStorageWrite({
    required String actionDescription,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
      return true;
    } catch (e) {
      AppLogger.error(
        'Failed to $actionDescription',
        subCategory: 'group_monitor',
        error: e,
      );
      return false;
    }
  }

  Future<void> _clearSelectedGroupsInternal() async {
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
