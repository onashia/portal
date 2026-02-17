import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers/fake_vrchat_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'derived providers return selected groups, lookup map, and count',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(
        groupMonitorProvider('usr_test').notifier,
      );
      await Future<void>.delayed(Duration.zero);

      final world = buildTestWorld(id: 'wrld_1', name: 'World One');

      notifier.state = GroupMonitorState(
        allGroups: [
          buildTestGroup(groupId: 'grp_alpha', name: 'Alpha'),
          buildTestGroup(groupId: 'grp_beta', name: 'Beta'),
        ],
        selectedGroupIds: {'grp_alpha'},
        groupInstances: {
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha_1',
                world: world,
                userCount: 3,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
            ),
          ],
          'grp_beta': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_beta_1',
                world: world,
                userCount: 4,
              ),
              groupId: 'grp_beta',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
            ),
          ],
        },
      );

      expect(container.read(groupMonitorSelectedGroupIdsProvider('usr_test')), {
        'grp_alpha',
      });

      final groupsById = container.read(
        groupMonitorAllGroupsByIdProvider('usr_test'),
      );
      expect(groupsById['grp_alpha']?.name, 'Alpha');
      expect(groupsById['grp_beta']?.name, 'Beta');

      expect(container.read(groupMonitorInstanceCountProvider('usr_test')), 2);
    },
  );

  test('sorted instances provider is deterministic and stable', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(groupMonitorProvider('usr_test').notifier);
    await Future<void>.delayed(Duration.zero);

    final world = buildTestWorld(id: 'wrld_1', name: 'World One');
    final tieTime = DateTime.utc(2026, 2, 13, 9, 30);

    notifier.state = GroupMonitorState(
      groupInstances: {
        'grp_alpha': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_latest',
              world: world,
              userCount: 5,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 10, 0),
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_null_detected',
              world: world,
              userCount: 1,
            ),
            groupId: 'grp_alpha',
          ),
        ],
        'grp_beta': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_tie_b',
              world: world,
              userCount: 2,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: tieTime,
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_tie_a',
              world: world,
              userCount: 2,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: tieTime,
          ),
        ],
      },
    );

    final sorted = container.read(
      groupMonitorSortedInstancesProvider('usr_test'),
    );
    final sortedIds = sorted.map((entry) => entry.instance.instanceId).toList();

    expect(sortedIds, [
      'inst_latest',
      'inst_tie_a',
      'inst_tie_b',
      'inst_null_detected',
    ]);
  });
}
