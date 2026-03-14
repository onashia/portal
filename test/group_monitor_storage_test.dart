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

  test('relay assist default and save', () async {
    final defaultValue = await GroupMonitorStorage.loadRelayAssistEnabled();
    expect(defaultValue, isTrue);

    await GroupMonitorStorage.saveRelayAssistEnabled(false);
    final loaded = await GroupMonitorStorage.loadRelayAssistEnabled();
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

  test('load boost settings handles invalid persisted timestamp', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.boostedGroupId: 'g1',
      StorageKeys.boostExpiresAt: 'not-a-timestamp',
    });

    final loaded = await GroupMonitorStorage.loadBoostSettings();

    expect(loaded.groupId, 'g1');
    expect(loaded.expiresAt, isNull);
  });

  test('load persisted state snapshot returns all settings together', () async {
    final expiresAt = DateTime.utc(2026, 3, 14, 12, 0);
    SharedPreferences.setMockInitialValues({
      StorageKeys.selectedGroupIds: ['g1', 'g2'],
      StorageKeys.autoInviteEnabled: false,
      StorageKeys.relayAssistEnabled: false,
      StorageKeys.boostedGroupId: 'g1',
      StorageKeys.boostExpiresAt: expiresAt.toIso8601String(),
    });

    final snapshot = await GroupMonitorStorage.loadPersistedState(
      relayAssistDefaultValue: true,
    );

    expect(snapshot.selectedGroupIds, {'g1', 'g2'});
    expect(snapshot.autoInviteEnabled, isFalse);
    expect(snapshot.relayAssistEnabled, isFalse);
    expect(snapshot.boostSettings.groupId, 'g1');
    expect(
      snapshot.boostSettings.expiresAt?.toIso8601String(),
      expiresAt.toIso8601String(),
    );
  });

  test(
    'load persisted state snapshot surfaces invalid boost timestamp as null',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.selectedGroupIds: ['g1'],
        StorageKeys.boostedGroupId: 'g1',
        StorageKeys.boostExpiresAt: 'not-a-timestamp',
      });

      final snapshot = await GroupMonitorStorage.loadPersistedState(
        relayAssistDefaultValue: true,
      );

      expect(snapshot.selectedGroupIds, {'g1'});
      expect(snapshot.boostSettings.groupId, 'g1');
      expect(snapshot.boostSettings.expiresAt, isNull);
    },
  );

  test(
    'load persisted state snapshot preserves selected groups when auto-invite value is malformed',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.selectedGroupIds: ['g1'],
        StorageKeys.autoInviteEnabled: 'nope',
        StorageKeys.relayAssistEnabled: false,
      });

      final snapshot = await GroupMonitorStorage.loadPersistedState(
        relayAssistDefaultValue: true,
      );

      expect(snapshot.selectedGroupIds, {'g1'});
      expect(snapshot.autoInviteEnabled, isTrue);
      expect(snapshot.relayAssistEnabled, isFalse);
    },
  );

  test(
    'load persisted state snapshot preserves valid fields when selected groups value is malformed',
    () async {
      final expiresAt = DateTime.utc(2026, 3, 14, 12, 0);
      SharedPreferences.setMockInitialValues({
        StorageKeys.selectedGroupIds: <Object>['g1', 2],
        StorageKeys.autoInviteEnabled: false,
        StorageKeys.relayAssistEnabled: false,
        StorageKeys.boostedGroupId: 'g1',
        StorageKeys.boostExpiresAt: expiresAt.toIso8601String(),
      });

      final snapshot = await GroupMonitorStorage.loadPersistedState(
        relayAssistDefaultValue: true,
      );

      expect(snapshot.selectedGroupIds, isEmpty);
      expect(snapshot.autoInviteEnabled, isFalse);
      expect(snapshot.relayAssistEnabled, isFalse);
      expect(snapshot.boostSettings.groupId, 'g1');
      expect(
        snapshot.boostSettings.expiresAt?.toIso8601String(),
        expiresAt.toIso8601String(),
      );
    },
  );

  test(
    'load persisted state snapshot falls back to relay assist default when value is malformed',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.selectedGroupIds: ['g1'],
        StorageKeys.relayAssistEnabled: 'disabled',
      });

      final snapshot = await GroupMonitorStorage.loadPersistedState(
        relayAssistDefaultValue: false,
      );

      expect(snapshot.selectedGroupIds, {'g1'});
      expect(snapshot.relayAssistEnabled, isFalse);
    },
  );

  test(
    'load persisted state snapshot ignores malformed boosted group id type',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.selectedGroupIds: ['g1'],
        StorageKeys.autoInviteEnabled: false,
        StorageKeys.boostedGroupId: 7,
        StorageKeys.boostExpiresAt: DateTime.utc(
          2026,
          3,
          14,
          12,
          0,
        ).toIso8601String(),
      });

      final snapshot = await GroupMonitorStorage.loadPersistedState(
        relayAssistDefaultValue: true,
      );

      expect(snapshot.selectedGroupIds, {'g1'});
      expect(snapshot.autoInviteEnabled, isFalse);
      expect(snapshot.boostSettings.groupId, isNull);
      expect(snapshot.boostSettings.expiresAt, isNotNull);
    },
  );

  test('save boost settings clears when either value is missing', () async {
    await GroupMonitorStorage.saveBoostSettings(
      groupId: 'g1',
      boostExpiresAt: null,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StorageKeys.boostedGroupId), isNull);
    expect(prefs.getString(StorageKeys.boostExpiresAt), isNull);

    await GroupMonitorStorage.saveBoostSettings(
      groupId: null,
      boostExpiresAt: DateTime.now(),
    );

    expect(prefs.getString(StorageKeys.boostedGroupId), isNull);
    expect(prefs.getString(StorageKeys.boostExpiresAt), isNull);
  });
}
