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

  Future<void> loadPersistedState() async {
    try {
      final snapshot = await GroupMonitorStorage.loadPersistedState(
        relayAssistDefaultValue: AppConstants.relayAssistEnabled,
      );
      final shouldApplyLoadedSelection =
          notifier.state.selectedGroupIds.isEmpty;
      final now = DateTime.now();
      final resolved = resolveLoadedBoostSettings(
        settings: snapshot.boostSettings,
        now: now,
      );
      // Use || so partial/corrupt boost data (only one field present) also
      // triggers the resolve-and-clear path in resolveLoadedBoostSettings.
      final hasPersistedBoostFields =
          snapshot.boostSettings.groupId != null ||
          snapshot.boostSettings.expiresAt != null;

      final nextSelectedGroupIds = shouldApplyLoadedSelection
          ? snapshot.selectedGroupIds
          : notifier.state.selectedGroupIds;
      if (!shouldApplyLoadedSelection) {
        AppLogger.debug(
          'Skipping loaded selected groups because selection already changed in memory',
          subCategory: 'group_monitor',
        );
      }

      notifier.state = notifier.state.copyWith(
        selectedGroupIds: nextSelectedGroupIds,
        autoInviteEnabled: snapshot.autoInviteEnabled,
        relayAssistEnabled: snapshot.relayAssistEnabled,
        isBoostActive: hasPersistedBoostFields
            ? resolved.boostExpiresAt != null &&
                  resolved.boostExpiresAt!.isAfter(now)
            : notifier.state.isBoostActive,
        boostedGroupId: hasPersistedBoostFields
            ? resolved.boostedGroupId
            : notifier.state.boostedGroupId,
        boostExpiresAt: hasPersistedBoostFields
            ? resolved.boostExpiresAt
            : notifier.state.boostExpiresAt,
      );

      AppLogger.debug(
        'Loaded ${snapshot.selectedGroupIds.length} selected groups from storage',
        subCategory: 'group_monitor',
      );
      AppLogger.debug(
        'Loaded auto-invite setting: ${snapshot.autoInviteEnabled}',
        subCategory: 'group_monitor',
      );
      AppLogger.debug(
        'Loaded relay assist setting: ${snapshot.relayAssistEnabled}',
        subCategory: 'group_monitor',
      );
      if (resolved.boostedGroupId != null && resolved.boostExpiresAt != null) {
        AppLogger.debug(
          'Loaded active boost settings for ${resolved.boostedGroupId}',
          subCategory: 'group_monitor',
        );
      }

      if (resolved.shouldClear) {
        await persistStorageWrite(
          actionDescription: 'persist boost settings',
          action: () => GroupMonitorStorage.saveBoostSettings(
            groupId: null,
            boostExpiresAt: null,
          ),
        );
        if (resolved.logExpired) {
          AppLogger.info(
            'Boost expired, reverting to normal polling',
            subCategory: 'group_monitor',
          );
        }
      }

      notifier._loopController.reconcileMonitoringForSelectionState();
    } catch (e) {
      AppLogger.error(
        'Failed to load persisted group monitor state',
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
