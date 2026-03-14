import 'package:shared_preferences/shared_preferences.dart';

import '../constants/storage_keys.dart';
import '../utils/app_logger.dart';

class GroupMonitorBoostSettings {
  final String? groupId;
  final DateTime? expiresAt;

  const GroupMonitorBoostSettings({this.groupId, this.expiresAt});
}

class GroupMonitorPersistedStateSnapshot {
  final Set<String> selectedGroupIds;
  final bool autoInviteEnabled;
  final bool relayAssistEnabled;
  final GroupMonitorBoostSettings boostSettings;

  const GroupMonitorPersistedStateSnapshot({
    required this.selectedGroupIds,
    required this.autoInviteEnabled,
    required this.relayAssistEnabled,
    required this.boostSettings,
  });
}

class GroupMonitorStorage {
  static Future<Set<String>> loadSelectedGroupIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadSelectedGroupIdsFromPrefs(prefs);
  }

  static Future<void> saveSelectedGroupIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(StorageKeys.selectedGroupIds, ids.toList());
  }

  static Future<bool> loadAutoInviteEnabled({bool defaultValue = true}) async {
    final prefs = await SharedPreferences.getInstance();
    return _loadAutoInviteEnabledFromPrefs(prefs, defaultValue: defaultValue);
  }

  static Future<void> saveAutoInviteEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.autoInviteEnabled, value);
  }

  static Future<bool> loadRelayAssistEnabled({bool defaultValue = true}) async {
    final prefs = await SharedPreferences.getInstance();
    return _loadRelayAssistEnabledFromPrefs(prefs, defaultValue: defaultValue);
  }

  static Future<void> saveRelayAssistEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.relayAssistEnabled, value);
  }

  static Future<GroupMonitorBoostSettings> loadBoostSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadBoostSettingsFromPrefs(prefs);
  }

  static Future<GroupMonitorPersistedStateSnapshot> loadPersistedState({
    bool relayAssistDefaultValue = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return GroupMonitorPersistedStateSnapshot(
      selectedGroupIds: _loadSelectedGroupIdsFromPrefs(prefs),
      autoInviteEnabled: _loadAutoInviteEnabledFromPrefs(prefs),
      relayAssistEnabled: _loadRelayAssistEnabledFromPrefs(
        prefs,
        defaultValue: relayAssistDefaultValue,
      ),
      boostSettings: _loadBoostSettingsFromPrefs(prefs),
    );
  }

  static Future<void> saveBoostSettings({
    required String? groupId,
    required DateTime? boostExpiresAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (groupId == null || boostExpiresAt == null) {
      await prefs.remove(StorageKeys.boostedGroupId);
      await prefs.remove(StorageKeys.boostExpiresAt);
      return;
    }

    await prefs.setString(StorageKeys.boostedGroupId, groupId);
    await prefs.setString(
      StorageKeys.boostExpiresAt,
      boostExpiresAt.toIso8601String(),
    );
  }

  static Future<void> clearSelectedGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.selectedGroupIds);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.selectedGroupIds);
    await prefs.remove(StorageKeys.boostedGroupId);
    await prefs.remove(StorageKeys.boostExpiresAt);
    await prefs.remove(StorageKeys.autoInviteEnabled);
    await prefs.remove(StorageKeys.relayAssistEnabled);
  }

  static Set<String> _loadSelectedGroupIdsFromPrefs(SharedPreferences prefs) {
    final rawValue = prefs.get(StorageKeys.selectedGroupIds);
    if (rawValue == null) {
      return {};
    }
    if (rawValue is List && rawValue.every((value) => value is String)) {
      return rawValue.cast<String>().toSet();
    }
    _logMalformedPreference(
      key: StorageKeys.selectedGroupIds,
      rawValue: rawValue,
      expectedType: 'List<String>',
    );
    return {};
  }

  static bool _loadAutoInviteEnabledFromPrefs(
    SharedPreferences prefs, {
    bool defaultValue = true,
  }) {
    return _loadBoolFromPrefs(
      prefs,
      key: StorageKeys.autoInviteEnabled,
      defaultValue: defaultValue,
    );
  }

  static bool _loadRelayAssistEnabledFromPrefs(
    SharedPreferences prefs, {
    required bool defaultValue,
  }) {
    return _loadBoolFromPrefs(
      prefs,
      key: StorageKeys.relayAssistEnabled,
      defaultValue: defaultValue,
    );
  }

  static GroupMonitorBoostSettings _loadBoostSettingsFromPrefs(
    SharedPreferences prefs,
  ) {
    final boostedGroupId = _loadStringFromPrefs(
      prefs,
      key: StorageKeys.boostedGroupId,
    );
    final expiresAtRaw = _loadStringFromPrefs(
      prefs,
      key: StorageKeys.boostExpiresAt,
    );
    final boostExpiresAt = expiresAtRaw == null
        ? null
        : DateTime.tryParse(expiresAtRaw);

    return GroupMonitorBoostSettings(
      groupId: boostedGroupId,
      expiresAt: boostExpiresAt,
    );
  }

  static bool _loadBoolFromPrefs(
    SharedPreferences prefs, {
    required String key,
    required bool defaultValue,
  }) {
    final rawValue = prefs.get(key);
    if (rawValue == null) {
      return defaultValue;
    }
    if (rawValue is bool) {
      return rawValue;
    }
    _logMalformedPreference(key: key, rawValue: rawValue, expectedType: 'bool');
    return defaultValue;
  }

  static String? _loadStringFromPrefs(
    SharedPreferences prefs, {
    required String key,
  }) {
    final rawValue = prefs.get(key);
    if (rawValue == null) {
      return null;
    }
    if (rawValue is String) {
      return rawValue;
    }
    _logMalformedPreference(
      key: key,
      rawValue: rawValue,
      expectedType: 'String',
    );
    return null;
  }

  static void _logMalformedPreference({
    required String key,
    required Object rawValue,
    required String expectedType,
  }) {
    AppLogger.warning(
      'Ignoring malformed persisted preference for $key: '
      'expected $expectedType, got ${rawValue.runtimeType}',
      subCategory: 'group_monitor',
    );
  }
}
