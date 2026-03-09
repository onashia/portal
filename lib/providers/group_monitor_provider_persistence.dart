part of 'group_monitor_provider.dart';

class _GroupMonitorPersistenceController {
  _GroupMonitorPersistenceController(this.notifier);

  final GroupMonitorNotifier notifier;

  void listenForAuthChanges() {
    notifier._listenAuthSession((previous, next) {
      final wasEligible =
          previous?.isAuthenticated == true && previous?.userId == notifier.arg;
      final isEligible = next.isAuthenticated && next.userId == notifier.arg;

      if (!isEligible) {
        if (notifier._currentState.isMonitoring) {
          notifier.stopMonitoring();
        } else {
          notifier._reconcileBaselineLoop();
          notifier._reconcileBoostLoop();
          notifier._reconcileRelayConnection();
        }
        return;
      }

      if (!wasEligible) {
        Future.microtask(() {
          if (!notifier._mounted) {
            return;
          }
          notifier._reconcileMonitoringForSelectionState();
        });
        return;
      }

      notifier._reconcileBaselineLoop();
      notifier._reconcileBoostLoop();
      notifier._reconcileRelayConnection();
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
        notifier._replaceState(
          notifier._currentState.copyWith(
            isBoostActive: resolved.boostExpiresAt!.isAfter(DateTime.now()),
            boostedGroupId: resolved.boostedGroupId,
            boostExpiresAt: resolved.boostExpiresAt,
          ),
        );
        AppLogger.debug(
          'Loaded active boost settings for ${resolved.boostedGroupId}',
          subCategory: 'group_monitor',
        );

        if (notifier._currentState.isMonitoring) {
          notifier._requestBoostRefresh(immediate: true);
        }
      }
      notifier._reconcileRelayConnection();
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
      notifier._replaceState(
        notifier._currentState.copyWith(autoInviteEnabled: enabled),
      );
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
      notifier._reconcileRelayConnection();
    }
  }

  Future<void> loadRelayAssistSetting() async {
    try {
      final enabled = await GroupMonitorStorage.loadRelayAssistEnabled(
        defaultValue: AppConstants.relayAssistEnabled,
      );
      notifier._replaceState(
        notifier._currentState.copyWith(relayAssistEnabled: enabled),
      );
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
      notifier._reconcileRelayConnection();
    }
  }

  Future<void> loadSelectedGroups() async {
    try {
      final selectedIds = await GroupMonitorStorage.loadSelectedGroupIds();
      final loadedSelection = selectedIds.toSet();
      final shouldApplyLoadedSelection =
          notifier._currentState.selectedGroupIds.isEmpty;
      if (shouldApplyLoadedSelection) {
        notifier._replaceState(
          notifier._currentState.copyWith(selectedGroupIds: loadedSelection),
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
      notifier._reconcileMonitoringForSelectionState();
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
        notifier._currentState.boostedGroupId != null ||
        notifier._currentState.boostExpiresAt != null;
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
        notifier._currentState.isMonitoring &&
        notifier._currentState.selectedGroupIds.isNotEmpty) {
      notifier._requestBaselineRefresh(immediate: true);
    }

    notifier._reconcileRelayConnection();
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
        notifier._currentState.selectedGroupIds,
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

      notifier._replaceState(
        notifier._currentState.copyWith(
          selectedGroupIds: {},
          groupInstances: {},
          newestInstanceId: null,
          isBoostActive: false,
          boostedGroupId: null,
          boostExpiresAt: null,
          groupErrors: {},
          relayConnected: false,
          lastRelayError: null,
        ),
      );
      notifier._reconcileMonitoringForSelectionState();
      notifier._reconcileRelayConnection();

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

extension GroupMonitorPersistenceExtension on GroupMonitorNotifier {
  void _listenForAuthChanges() => _persistenceController.listenForAuthChanges();

  Future<void> _loadBoostSettings() =>
      _persistenceController.loadBoostSettings();

  Future<void> _loadAutoInviteSetting() =>
      _persistenceController.loadAutoInviteSetting();

  Future<void> _loadRelayAssistSetting() =>
      _persistenceController.loadRelayAssistSetting();

  Future<void> _loadSelectedGroups() =>
      _persistenceController.loadSelectedGroups();

  Future<void> _clearBoost({
    required bool persist,
    required bool logExpired,
    bool requestBaselineRecovery = true,
  }) {
    return _persistenceController.clearBoost(
      persist: persist,
      logExpired: logExpired,
      requestBaselineRecovery: requestBaselineRecovery,
    );
  }

  Future<void> _persistBoostSettings({
    required String? groupId,
    required DateTime? boostExpiresAt,
  }) {
    return _persistenceController.persistBoostSettings(
      groupId: groupId,
      boostExpiresAt: boostExpiresAt,
    );
  }

  Future<void> _saveSelectedGroups() =>
      _persistenceController.saveSelectedGroups();

  Future<bool> _persistStorageWrite({
    required String actionDescription,
    required Future<void> Function() action,
  }) {
    return _persistenceController.persistStorageWrite(
      actionDescription: actionDescription,
      action: action,
    );
  }

  Future<void> _clearSelectedGroupsInternal() =>
      _persistenceController.clearSelectedGroupsInternal();
}
