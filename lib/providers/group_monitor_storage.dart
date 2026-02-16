import 'package:shared_preferences/shared_preferences.dart';

import '../constants/storage_keys.dart';

class GroupMonitorBoostSettings {
  final String? groupId;
  final DateTime? expiresAt;

  const GroupMonitorBoostSettings({this.groupId, this.expiresAt});
}

class GroupMonitorStorage {
  static Future<Set<String>> loadSelectedGroupIds() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedIds = prefs.getStringList(StorageKeys.selectedGroupIds) ?? [];
    return selectedIds.toSet();
  }

  static Future<void> saveSelectedGroupIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(StorageKeys.selectedGroupIds, ids.toList());
  }

  static Future<bool> loadAutoInviteEnabled({bool defaultValue = true}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageKeys.autoInviteEnabled) ?? defaultValue;
  }

  static Future<void> saveAutoInviteEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.autoInviteEnabled, value);
  }

  static Future<GroupMonitorBoostSettings> loadBoostSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final boostedGroupId = prefs.getString(StorageKeys.boostedGroupId);
    final expiresAtRaw = prefs.getString(StorageKeys.boostExpiresAt);
    final boostExpiresAt = expiresAtRaw == null
        ? null
        : DateTime.tryParse(expiresAtRaw);

    return GroupMonitorBoostSettings(
      groupId: boostedGroupId,
      expiresAt: boostExpiresAt,
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
  }
}
