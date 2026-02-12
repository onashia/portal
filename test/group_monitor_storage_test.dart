import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:portal/constants/storage_keys.dart';
import 'package:portal/providers/group_monitor_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('selected groups save/load/clear', () async {
    final ids = {'g1', 'g2'};

    await GroupMonitorStorage.saveSelectedGroupIds(ids);
    final loaded = await GroupMonitorStorage.loadSelectedGroupIds();
    expect(loaded, ids);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(StorageKeys.selectedGroupIds);
    expect(stored, isNotNull);
    expect(stored, containsAll(ids));

    await GroupMonitorStorage.clearSelectedGroups();
    final cleared = await GroupMonitorStorage.loadSelectedGroupIds();
    expect(cleared, isEmpty);
    expect(prefs.getStringList(StorageKeys.selectedGroupIds), isNull);
  });

  test('auto-invite default and save', () async {
    final defaultValue = await GroupMonitorStorage.loadAutoInviteEnabled();
    expect(defaultValue, isTrue);

    await GroupMonitorStorage.saveAutoInviteEnabled(false);
    final loaded = await GroupMonitorStorage.loadAutoInviteEnabled();
    expect(loaded, isFalse);
  });

  test('boost settings save/load/clear', () async {
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));

    await GroupMonitorStorage.saveBoostSettings(
      groupId: 'g1',
      boostExpiresAt: expiresAt,
    );

    final loaded = await GroupMonitorStorage.loadBoostSettings();
    expect(loaded.groupId, 'g1');
    expect(loaded.expiresAt?.toIso8601String(), expiresAt.toIso8601String());

    await GroupMonitorStorage.saveBoostSettings(
      groupId: null,
      boostExpiresAt: null,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.boostedGroupId), isNull);
    expect(prefs.getString(StorageKeys.boostExpiresAt), isNull);
  });
}
