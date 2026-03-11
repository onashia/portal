// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
// This part-file's controller coordinates GroupMonitorNotifier internals within
// the same library and intentionally reads/writes Riverpod's protected members.

part of 'group_monitor_provider.dart';

class _GroupMonitorPersistenceController {
  _GroupMonitorPersistenceController(this.notifier);

  final GroupMonitorNotifier notifier;

  void listenForAuthChanges() {
    notifier.ref.listen<AuthSessionSnapshot>(authSessionSnapshotProvider, (
      previous,
      next,
    ) {
      final wasEligible =
          previous?.isAuthenticated == true && previous?.userId == notifier.arg;
      final isEligible = next.isAuthenticated && next.userId == notifier.arg;

      if (!isEligible) {
        if (notifier.state.isMonitoring) {
          notifier.stopMonitoring();
        } else {
          notifier._loopController.reconcileBaselineLoop();
          notifier._loopController.reconcileBoostLoop();
          notifier._relayController.reconcileConnection();
        }
        return;
      }

      if (!wasEligible) {
        Future.microtask(() {
          if (!notifier.ref.mounted) {
            return;
          }
          notifier._loopController.reconcileMonitoringForSelectionState();
        });
        return;
      }

      notifier._loopController.reconcileBaselineLoop();
      notifier._loopController.reconcileBoostLoop();
      notifier._relayController.reconcileConnection();
    });
  }

  Future<void> loadBoostSettings() async {
    try {
      final settings = await GroupMonitorStorage.loadBoostSettings();
      final resolved = resolveLoadedBoostSettings(
        settings: settings,
        now: DateTime.now(),
      );

      if (resolved.shouldClear) {
        await clearBoost(persist: true, logExpired: resolved.logExpired);
        return;
      }

      if (resolved.boostedGroupId != null && resolved.boostExpiresAt != null) {
        notifier.state = notifier.state.copyWith(
          isBoostActive: resolved.boostExpiresAt!.isAfter(DateTime.now()),
          boostedGroupId: resolved.boostedGroupId,
          boostExpiresAt: resolved.boostExpiresAt,
        );
        AppLogger.debug(
          'Loaded active boost settings for ${resolved.boostedGroupId}',
          subCategory: 'group_monitor',
        );

        if (notifier.state.isMonitoring) {
          notifier._loopController.requestBoostRefresh(immediate: true);
        }
      }
      notifier._relayController.reconcileConnection();
    } catch (e) {
      AppLogger.error(
        'Failed to load boost settings',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> loadAutoInviteSetting() async {
    try {
      final enabled = await GroupMonitorStorage.loadAutoInviteEnabled();
      notifier.state = notifier.state.copyWith(autoInviteEnabled: enabled);
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
    } finally {
      notifier._relayController.reconcileConnection();
    }
  }

  Future<void> loadRelayAssistSetting() async {
    try {
      final enabled = await GroupMonitorStorage.loadRelayAssistEnabled(
        defaultValue: AppConstants.relayAssistEnabled,
      );
      notifier.state = notifier.state.copyWith(relayAssistEnabled: enabled);
      AppLogger.debug(
        'Loaded relay assist setting: $enabled',
        subCategory: 'group_monitor',
      );
    } catch (e) {
      AppLogger.error(
        'Failed to load relay assist setting',
        subCategory: 'group_monitor',
        error: e,
      );
    } finally {
      notifier._relayController.reconcileConnection();
    }
  }

  Future<void> loadSelectedGroups() async {
    try {
      final selectedIds = await GroupMonitorStorage.loadSelectedGroupIds();
      final loadedSelection = selectedIds.toSet();
      final shouldApplyLoadedSelection =
          notifier.state.selectedGroupIds.isEmpty;
      if (shouldApplyLoadedSelection) {
        notifier.state = notifier.state.copyWith(
          selectedGroupIds: loadedSelection,
        );
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
      notifier._loopController.reconcileMonitoringForSelectionState();
    } catch (e) {
      AppLogger.error(
        'Failed to load selected groups',
        subCategory: 'group_monitor',
        error: e,
      );
    }
  }

  Future<void> clearBoost({
    required bool persist,
    required bool logExpired,
    bool requestBaselineRecovery = true,
  }) async {
    final hadBoost =
        notifier.state.boostedGroupId != null ||
        notifier.state.boostExpiresAt != null;
    notifier._boostLoop.cancelTimer();
    notifier._boostLoop.clearPending();
    notifier._resetBoostRuntimeTracking();
    notifier._applyBoostState(groupId: null, expiresAt: null);

    if (persist) {
      await persistBoostSettings(groupId: null, boostExpiresAt: null);
    }

    if (logExpired) {
      AppLogger.info(
        'Boost expired, reverting to normal polling',
        subCategory: 'group_monitor',
      );
    }

    if (requestBaselineRecovery &&
        hadBoost &&
        notifier.state.isMonitoring &&
        notifier.state.selectedGroupIds.isNotEmpty) {
      notifier._loopController.requestBaselineRefresh(immediate: true);
    }

    notifier._relayController.reconcileConnection();
  }

  Future<void> persistBoostSettings({
    required String? groupId,
    required DateTime? boostExpiresAt,
  }) async {
    await persistStorageWrite(
      actionDescription: 'persist boost settings',
      action: () => GroupMonitorStorage.saveBoostSettings(
        groupId: groupId,
        boostExpiresAt: boostExpiresAt,
      ),
    );
  }

  Future<void> saveSelectedGroups() async {
    await persistStorageWrite(
      actionDescription: 'save selected groups',
      action: () => GroupMonitorStorage.saveSelectedGroupIds(
        notifier.state.selectedGroupIds,
      ),
    );
  }

  Future<bool> persistStorageWrite({
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

  Future<void> clearSelectedGroupsInternal() async {
    try {
      await GroupMonitorStorage.clearSelectedGroups();
      await clearBoost(
        persist: true,
        logExpired: false,
        requestBaselineRecovery: false,
      );

      notifier.state = notifier.state.copyWith(
        selectedGroupIds: {},
        groupInstances: {},
        newestInstanceId: null,
        isBoostActive: false,
        boostedGroupId: null,
        boostExpiresAt: null,
        groupErrors: {},
        relayConnected: false,
        lastRelayError: null,
      );
      notifier._loopController.reconcileMonitoringForSelectionState();
      notifier._relayController.reconcileConnection();

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
