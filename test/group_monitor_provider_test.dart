import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/group_monitor_storage.dart';

import 'test_helpers/fake_vrchat_models.dart';

void main() {
  group('resolveLoadedBoostSettings', () {
    test('keeps valid future boost settings', () {
      final now = DateTime.utc(2026, 2, 13, 10);
      final settings = GroupMonitorBoostSettings(
        groupId: 'grp_alpha',
        expiresAt: now.add(const Duration(minutes: 5)),
      );

      final result = resolveLoadedBoostSettings(settings: settings, now: now);

      expect(result.shouldClear, isFalse);
      expect(result.logExpired, isFalse);
      expect(result.boostedGroupId, 'grp_alpha');
      expect(result.boostExpiresAt, settings.expiresAt);
    });

    test('clears expired boost settings and marks as expired', () {
      final now = DateTime.utc(2026, 2, 13, 10);
      final settings = GroupMonitorBoostSettings(
        groupId: 'grp_alpha',
        expiresAt: now.subtract(const Duration(seconds: 1)),
      );

      final result = resolveLoadedBoostSettings(settings: settings, now: now);

      expect(result.shouldClear, isTrue);
      expect(result.logExpired, isTrue);
      expect(result.boostedGroupId, isNull);
      expect(result.boostExpiresAt, isNull);
    });

    test('clears partial persisted boost settings without expiry log', () {
      final now = DateTime.utc(2026, 2, 13, 10);

      final missingExpiry = resolveLoadedBoostSettings(
        settings: const GroupMonitorBoostSettings(groupId: 'grp_alpha'),
        now: now,
      );

      final missingGroupId = resolveLoadedBoostSettings(
        settings: GroupMonitorBoostSettings(expiresAt: now),
        now: now,
      );

      expect(missingExpiry.shouldClear, isTrue);
      expect(missingExpiry.logExpired, isFalse);
      expect(missingGroupId.shouldClear, isTrue);
      expect(missingGroupId.logExpired, isFalse);
    });
  });

  group('mergeFetchedGroupInstances', () {
    test(
      'preserves detection time for existing instances and marks new ones',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');
        final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);
        final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);

        final previousInstances = [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_existing',
              world: world,
              userCount: 5,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: previousDetectedAt,
          ),
        ];

        final fetchedInstances = [
          buildTestInstance(
            instanceId: 'inst_existing',
            world: world,
            userCount: 6,
          ),
          buildTestInstance(instanceId: 'inst_new', world: world, userCount: 3),
        ];

        final merged = mergeFetchedGroupInstances(
          groupId: 'grp_alpha',
          fetchedInstances: fetchedInstances,
          previousInstances: previousInstances,
          detectedAt: detectedAt,
        );

        expect(merged.mergedInstances, hasLength(2));
        expect(merged.newInstances, hasLength(1));
        expect(merged.newInstances.first.instance.instanceId, 'inst_new');

        final existingMerged = merged.mergedInstances.firstWhere(
          (entry) => entry.instance.instanceId == 'inst_existing',
        );
        final newMerged = merged.mergedInstances.firstWhere(
          (entry) => entry.instance.instanceId == 'inst_new',
        );

        expect(existingMerged.firstDetectedAt, previousDetectedAt);
        expect(newMerged.firstDetectedAt, detectedAt);
      },
    );
  });

  group('areGroupInstanceListsEquivalent', () {
    test('returns true for equivalent lists even if order differs', () {
      final worldA = buildTestWorld(id: 'wrld_a', name: 'World A');
      final worldB = buildTestWorld(id: 'wrld_b', name: 'World B');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previous = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: worldA,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_b',
            world: worldB,
            userCount: 4,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];
      final next = [previous[1], previous[0]];

      expect(areGroupInstanceListsEquivalent(previous, next), isTrue);
    });

    test('returns false when nUsers changes', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previous = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];
      final next = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 5,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];

      expect(areGroupInstanceListsEquivalent(previous, next), isFalse);
    });

    test('returns false when world name changes', () {
      final worldBefore = buildTestWorld(id: 'wrld_a', name: 'World A');
      final worldAfter = buildTestWorld(id: 'wrld_a', name: 'World A Prime');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previous = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: worldBefore,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];
      final next = [
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: worldAfter,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: detectedAt,
        ),
      ];

      expect(areGroupInstanceListsEquivalent(previous, next), isFalse);
    });
  });

  group('areGroupInstancesByGroupEquivalent', () {
    test('returns false when one group payload changes', () {
      final world = buildTestWorld(id: 'wrld_1', name: 'World One');

      final previous = {
        'grp_alpha': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
          ),
        ],
        'grp_beta': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_beta',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
          ),
        ],
      };
      final next = {
        'grp_alpha': previous['grp_alpha']!,
        'grp_beta': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_beta',
              world: world,
              userCount: 8,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
          ),
        ],
      };

      expect(areGroupInstancesByGroupEquivalent(previous, next), isFalse);
    });
  });

  group('newestInstanceIdFromGroupInstances', () {
    test(
      'returns newest across groups and remains correct after group replacement',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');

        final initial = {
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha_old',
                world: world,
                userCount: 4,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
            ),
          ],
          'grp_beta': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_beta_new',
                world: world,
                userCount: 7,
              ),
              groupId: 'grp_beta',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
            ),
          ],
        };

        expect(newestInstanceIdFromGroupInstances(initial), 'inst_beta_new');

        final boostedUpdate = {
          ...initial,
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha_boosted',
                world: world,
                userCount: 10,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 10, 0),
            ),
          ],
        };

        expect(
          newestInstanceIdFromGroupInstances(boostedUpdate),
          'inst_alpha_boosted',
        );
      },
    );

    test(
      'remains correct with unchanged groups and one changed group payload',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');

        final previous = {
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha',
                world: world,
                userCount: 4,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
            ),
          ],
          'grp_beta': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_beta',
                world: world,
                userCount: 6,
              ),
              groupId: 'grp_beta',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
            ),
          ],
        };

        final next = {
          'grp_alpha': previous['grp_alpha']!,
          'grp_beta': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_beta_new',
                world: world,
                userCount: 7,
              ),
              groupId: 'grp_beta',
              firstDetectedAt: DateTime.utc(2026, 2, 13, 10, 0),
            ),
          ],
        };

        expect(newestInstanceIdFromGroupInstances(previous), 'inst_beta');
        expect(newestInstanceIdFromGroupInstances(next), 'inst_beta_new');
      },
    );
  });
}
