import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/api_rate_limit_provider.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/group_monitor_storage.dart';
import 'package:portal/providers/polling_lifecycle.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'test_helpers/auth_test_harness.dart';
import 'test_helpers/fake_vrchat_models.dart';

({
  ProviderContainer container,
  TestAuthNotifier authNotifier,
  NotifierProvider<GroupMonitorNotifier, GroupMonitorState> provider,
  GroupMonitorNotifier notifier,
})
createGroupMonitorHarness({
  required AuthState initialAuthState,
  String userId = 'usr_test',
  List<dynamic> overrides = const <dynamic>[],
}) {
  final authHarness = createAuthHarness(
    initialAuthState: initialAuthState,
    overrides: overrides,
  );
  final provider = groupMonitorProvider(userId);
  final notifier = authHarness.container.read(provider.notifier);
  return (
    container: authHarness.container,
    authNotifier: authHarness.authNotifier,
    provider: provider,
    notifier: notifier,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  group('mergeFetchedGroupInstancesWithDiff', () {
    test(
      'reuses previous reference when payload is unchanged but reordered',
      () {
        final worldA = buildTestWorld(id: 'wrld_a', name: 'World A');
        final worldB = buildTestWorld(id: 'wrld_b', name: 'World B');
        final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);

        final previousInstances = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_a',
              world: worldA,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 8, 0),
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_b',
              world: worldB,
              userCount: 5,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 9, 0),
          ),
        ];

        final fetchedInstances = <Instance>[
          previousInstances[1].instance,
          previousInstances[0].instance,
        ];

        final merged = mergeFetchedGroupInstancesWithDiff(
          groupId: 'grp_alpha',
          fetchedInstances: fetchedInstances,
          previousInstances: previousInstances,
          detectedAt: detectedAt,
        );

        expect(merged.didChange, isFalse);
        expect(merged.newInstances, isEmpty);
        expect(identical(merged.effectiveInstances, previousInstances), isTrue);
      },
    );

    test(
      'marks add/remove changes and keeps only new entries in newInstances',
      () {
        final worldA = buildTestWorld(id: 'wrld_a', name: 'World A');
        final worldB = buildTestWorld(id: 'wrld_b', name: 'World B');
        final worldC = buildTestWorld(id: 'wrld_c', name: 'World C');
        final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
        final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 30);

        final previousInstances = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_a',
              world: worldA,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: previousDetectedAt,
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_b',
              world: worldB,
              userCount: 4,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: previousDetectedAt,
          ),
        ];

        final fetchedInstances = <Instance>[
          buildTestInstance(instanceId: 'inst_a', world: worldA, userCount: 3),
          buildTestInstance(instanceId: 'inst_c', world: worldC, userCount: 8),
        ];

        final merged = mergeFetchedGroupInstancesWithDiff(
          groupId: 'grp_alpha',
          fetchedInstances: fetchedInstances,
          previousInstances: previousInstances,
          detectedAt: detectedAt,
        );

        expect(merged.didChange, isTrue);
        expect(
          identical(merged.effectiveInstances, previousInstances),
          isFalse,
        );
        expect(merged.newInstances, hasLength(1));
        expect(merged.newInstances.single.instance.instanceId, 'inst_c');
        expect(merged.newInstances.single.firstDetectedAt, detectedAt);

        final preserved = merged.effectiveInstances.firstWhere(
          (entry) => entry.instance.instanceId == 'inst_a',
        );
        expect(preserved.firstDetectedAt, previousDetectedAt);
      },
    );

    test('marks payload changes when existing instance fields differ', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
      final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previousInstances = <GroupInstanceWithGroup>[
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
      ];

      final fetchedInstances = <Instance>[
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 9),
      ];

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: 'grp_alpha',
        fetchedInstances: fetchedInstances,
        previousInstances: previousInstances,
        detectedAt: detectedAt,
      );

      expect(merged.didChange, isTrue);
      expect(merged.newInstances, isEmpty);
      expect(identical(merged.effectiveInstances, previousInstances), isFalse);
    });

    test('detects when previous instances are replaced by duplicates', () {
      final world = buildTestWorld(id: 'wrld_a', name: 'World A');
      final detectedAt = DateTime.utc(2026, 2, 13, 10, 0);
      final previousDetectedAt = DateTime.utc(2026, 2, 13, 9, 0);

      final previousInstances = <GroupInstanceWithGroup>[
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_a',
            world: world,
            userCount: 5,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
        GroupInstanceWithGroup(
          instance: buildTestInstance(
            instanceId: 'inst_b',
            world: world,
            userCount: 3,
          ),
          groupId: 'grp_alpha',
          firstDetectedAt: previousDetectedAt,
        ),
      ];

      final fetchedInstances = <Instance>[
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
      ];

      final merged = mergeFetchedGroupInstancesWithDiff(
        groupId: 'grp_alpha',
        fetchedInstances: fetchedInstances,
        previousInstances: previousInstances,
        detectedAt: detectedAt,
      );

      expect(merged.didChange, isTrue);
      expect(merged.newInstances, isEmpty);
      expect(merged.effectiveInstances, hasLength(2));
      expect(merged.effectiveInstances[0].instance.instanceId, 'inst_a');
      expect(merged.effectiveInstances[1].instance.instanceId, 'inst_a');
      expect(merged.effectiveInstances[0].firstDetectedAt, previousDetectedAt);
      expect(merged.effectiveInstances[1].firstDetectedAt, previousDetectedAt);
    });
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

    test(
      'returns false when next contains duplicates replacing previous items',
      () {
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
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_b',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];

        final next = [previous[0], previous[0]];

        expect(areGroupInstanceListsEquivalent(previous, next), isFalse);
      },
    );
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

  group('group instance change tracking', () {
    test('treats key-set mismatch as changed', () {
      final world = buildTestWorld(id: 'wrld_1', name: 'World One');
      final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);
      final groupInstances = <String, List<GroupInstanceWithGroup>>{
        'grp_alpha': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ],
      };

      expect(
        hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          groupInstances: groupInstances,
        ),
        isTrue,
      );
      expect(
        hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha'},
          groupInstances: {...groupInstances, 'grp_beta': []},
        ),
        isTrue,
      );
    });

    test(
      'reuses previous map reference when keys and payloads are unchanged',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');
        final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);
        final previousAlpha = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousBeta = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_beta',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': previousAlpha,
          'grp_beta': previousBeta,
        };

        var didInstancesChange = hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          groupInstances: previousGroupInstances,
        );
        final mergedAlpha = [previousAlpha.first];
        final alphaDidChange = !areGroupInstanceListsEquivalent(
          previousAlpha,
          mergedAlpha,
        );
        final resolvedAlpha = alphaDidChange ? mergedAlpha : previousAlpha;
        final mergedBeta = [previousBeta.first];
        final betaDidChange = !areGroupInstanceListsEquivalent(
          previousBeta,
          mergedBeta,
        );
        final resolvedBeta = betaDidChange ? mergedBeta : previousBeta;
        didInstancesChange =
            didInstancesChange || alphaDidChange || betaDidChange;

        final nextGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': resolvedAlpha,
          'grp_beta': resolvedBeta,
        };
        final selectedGroupInstances = didInstancesChange
            ? nextGroupInstances
            : previousGroupInstances;

        expect(didInstancesChange, isFalse);
        expect(identical(resolvedAlpha, previousAlpha), isTrue);
        expect(identical(resolvedBeta, previousBeta), isTrue);
        expect(
          identical(selectedGroupInstances, previousGroupInstances),
          isTrue,
        );
      },
    );

    test(
      'updates changed group while preserving unchanged group list references',
      () {
        final world = buildTestWorld(id: 'wrld_1', name: 'World One');
        final detectedAt = DateTime.utc(2026, 2, 13, 9, 0);
        final previousAlpha = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousBeta = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_beta',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_beta',
            firstDetectedAt: detectedAt,
          ),
        ];
        final previousGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': previousAlpha,
          'grp_beta': previousBeta,
        };

        var didInstancesChange = hasGroupInstanceKeyMismatch(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          groupInstances: previousGroupInstances,
        );
        final mergedAlpha = <GroupInstanceWithGroup>[
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_alpha',
              world: world,
              userCount: 8,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: detectedAt,
          ),
        ];
        final alphaDidChange = !areGroupInstanceListsEquivalent(
          previousAlpha,
          mergedAlpha,
        );
        final resolvedAlpha = alphaDidChange ? mergedAlpha : previousAlpha;
        final mergedBeta = [previousBeta.first];
        final betaDidChange = !areGroupInstanceListsEquivalent(
          previousBeta,
          mergedBeta,
        );
        final resolvedBeta = betaDidChange ? mergedBeta : previousBeta;
        didInstancesChange =
            didInstancesChange || alphaDidChange || betaDidChange;

        final nextGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': resolvedAlpha,
          'grp_beta': resolvedBeta,
        };
        final selectedGroupInstances = didInstancesChange
            ? nextGroupInstances
            : previousGroupInstances;

        expect(didInstancesChange, isTrue);
        expect(
          identical(selectedGroupInstances, previousGroupInstances),
          isFalse,
        );
        expect(
          identical(selectedGroupInstances['grp_alpha'], previousAlpha),
          isFalse,
        );
        expect(
          identical(selectedGroupInstances['grp_beta'], previousBeta),
          isTrue,
        );
      },
    );
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

  group('fetchGroupInstancesChunked', () {
    test('limits concurrency and preserves ordered results', () async {
      const orderedGroupIds = [
        'grp_alpha',
        'grp_beta',
        'grp_gamma',
        'grp_delta',
      ];
      final releaseByGroup = {
        for (final groupId in orderedGroupIds) groupId: Completer<void>(),
      };
      final started = <String>[];
      var activeRequests = 0;
      var peakConcurrentRequests = 0;

      final resultFuture = fetchGroupInstancesChunked(
        orderedGroupIds: orderedGroupIds,
        maxConcurrentRequests: 2,
        fetchGroupInstances: (groupId) async {
          started.add(groupId);
          activeRequests += 1;
          if (activeRequests > peakConcurrentRequests) {
            peakConcurrentRequests = activeRequests;
          }

          await releaseByGroup[groupId]!.future;
          activeRequests -= 1;
          return null;
        },
      );

      await pumpEventQueue();
      expect(started, equals(['grp_alpha', 'grp_beta']));

      releaseByGroup['grp_alpha']!.complete();
      releaseByGroup['grp_beta']!.complete();
      await pumpEventQueue();
      expect(
        started,
        equals(['grp_alpha', 'grp_beta', 'grp_gamma', 'grp_delta']),
      );

      releaseByGroup['grp_gamma']!.complete();
      releaseByGroup['grp_delta']!.complete();
      final results = await resultFuture;

      expect(peakConcurrentRequests, lessThanOrEqualTo(2));
      expect(
        results.map((entry) => entry.groupId).toList(growable: false),
        equals(orderedGroupIds),
      );
    });

    test('throws when maxConcurrentRequests is less than 1', () async {
      expect(
        () => fetchGroupInstancesChunked(
          orderedGroupIds: const ['grp_alpha'],
          maxConcurrentRequests: 0,
          fetchGroupInstances: (_) async => null,
        ),
        throwsArgumentError,
      );
    });
  });

  group('shouldAttemptSelfInviteForInstance', () {
    Instance buildInstance({
      required String worldId,
      required String instanceId,
      required bool? canRequestInvite,
    }) {
      final world = buildTestWorld(
        id: worldId.isEmpty ? 'wrld_fallback' : worldId,
        name: 'World',
      );
      return Instance(
        canRequestInvite: canRequestInvite,
        clientNumber: 'unknown',
        id: 'inst_${instanceId.isEmpty ? 'fallback' : instanceId}',
        instanceId: instanceId,
        location: '$worldId:$instanceId',
        nUsers: 5,
        name: 'Instance $instanceId',
        photonRegion: Region.us,
        platforms: InstancePlatforms(android: 0, standalonewindows: 5),
        queueEnabled: false,
        queueSize: 0,
        recommendedCapacity: 16,
        region: InstanceRegion.us,
        secureName: 'secure-${instanceId.isEmpty ? 'fallback' : instanceId}',
        strict: false,
        tags: const [],
        type: InstanceType.group,
        userCount: 5,
        world: world,
        worldId: worldId,
      );
    }

    test('returns false when canRequestInvite is explicitly false', () {
      final instance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        canRequestInvite: false,
      );

      expect(shouldAttemptSelfInviteForInstance(instance), isFalse);
    });

    test('returns true when canRequestInvite is true', () {
      final instance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        canRequestInvite: true,
      );

      expect(shouldAttemptSelfInviteForInstance(instance), isTrue);
    });

    test('returns true when canRequestInvite is null', () {
      final instance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: 'inst_alpha',
        canRequestInvite: null,
      );

      expect(shouldAttemptSelfInviteForInstance(instance), isTrue);
    });

    test('returns false when worldId or instanceId is invalid', () {
      final missingWorld = buildInstance(
        worldId: '',
        instanceId: 'inst_alpha',
        canRequestInvite: true,
      );
      final missingInstance = buildInstance(
        worldId: 'wrld_alpha',
        instanceId: '',
        canRequestInvite: true,
      );

      expect(shouldAttemptSelfInviteForInstance(missingWorld), isFalse);
      expect(shouldAttemptSelfInviteForInstance(missingInstance), isFalse);
    });
  });

  group('pending refresh decisions', () {
    test('queues pending refresh only when active and in-flight', () {
      final queueWhenActive = shouldRequestImmediateRefresh(
        isActive: true,
        isInFlight: true,
        immediate: true,
      );
      expect(queueWhenActive.shouldQueuePending, isTrue);

      final noQueueWhenIdle = shouldRequestImmediateRefresh(
        isActive: true,
        isInFlight: false,
        immediate: true,
      );
      expect(noQueueWhenIdle.shouldQueuePending, isFalse);

      final noQueueWhenInactive = shouldRequestImmediateRefresh(
        isActive: false,
        isInFlight: true,
        immediate: true,
      );
      expect(noQueueWhenInactive.shouldQueuePending, isFalse);
    });

    test('drains only when pending and not currently fetching', () {
      final drainsWhenEligible = shouldDrainPendingRefresh(
        isMounted: true,
        isInFlight: false,
        hasPendingRefresh: true,
        isActive: true,
      );
      expect(drainsWhenEligible, isTrue);

      expect(
        shouldDrainPendingRefresh(
          isMounted: true,
          isInFlight: true,
          hasPendingRefresh: true,
          isActive: true,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingRefresh(
          isMounted: true,
          isInFlight: false,
          hasPendingRefresh: true,
          isActive: false,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingRefresh(
          isMounted: true,
          isInFlight: false,
          hasPendingRefresh: false,
          isActive: true,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingRefresh(
          isMounted: false,
          isInFlight: false,
          hasPendingRefresh: true,
          isActive: true,
        ),
        isFalse,
      );
    });
  });

  group('auth session polling guards', () {
    test('isSessionEligible requires auth and matching user id', () {
      expect(
        isSessionEligible(
          isAuthenticated: true,
          authenticatedUserId: 'usr_test',
          expectedUserId: 'usr_test',
        ),
        isTrue,
      );
      expect(
        isSessionEligible(
          isAuthenticated: false,
          authenticatedUserId: 'usr_test',
          expectedUserId: 'usr_test',
        ),
        isFalse,
      );
      expect(
        isSessionEligible(
          isAuthenticated: true,
          authenticatedUserId: 'usr_other',
          expectedUserId: 'usr_test',
        ),
        isFalse,
      );
    });

    test(
      'stops monitoring when auth transitions away from authenticated',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );

        authNotifier.setData(unauthenticatedAuthState());
        await Future<void>.delayed(Duration.zero);

        expect(container.read(provider).isMonitoring, isFalse);
      },
    );

    test(
      'fetchGroupInstances is skipped when authenticated user id mismatches',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_other'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );

        await notifier.fetchGroupInstances();

        expect(container.read(apiCallCounterProvider).totalCalls, 0);
      },
    );

    test(
      'timer-driven fetch remains guarded when auth user changes after scheduling',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
        );
        notifier.startMonitoring();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final callsBeforeAuthChange = container
            .read(apiCallCounterProvider)
            .totalCalls;

        authNotifier.setData(authenticatedAuthState(userId: 'usr_other'));
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          container.read(apiCallCounterProvider).totalCalls,
          callsBeforeAuthChange,
        );
        expect(container.read(provider).isMonitoring, isFalse);
      },
    );

    test(
      'auth transition does not start monitoring with empty selection',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: unauthenticatedAuthState(),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = const GroupMonitorState(selectedGroupIds: <String>{});
        authNotifier.setData(authenticatedAuthState(userId: 'usr_test'));
        expect(container.read(provider).isMonitoring, isFalse);
      },
    );

    test(
      'auth transition starts monitoring when selected groups exist',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: unauthenticatedAuthState(),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
        );
        authNotifier.setData(authenticatedAuthState(userId: 'usr_test'));
        await Future<void>.delayed(Duration.zero);
        expect(container.read(provider).isMonitoring, isTrue);
        notifier.stopMonitoring();
      },
    );

    test(
      'toggleGroupSelection starts monitoring when first group is selected',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState();

        notifier.toggleGroupSelection('grp_alpha');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final currentState = container.read(provider);
        expect(currentState.selectedGroupIds, contains('grp_alpha'));
        expect(currentState.isMonitoring, isTrue);
      },
    );

    test(
      'toggleGroupSelection restarts monitoring after deselect/reselect',
      () {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState();

        notifier.toggleGroupSelection('grp_alpha');
        expect(container.read(provider).isMonitoring, isTrue);

        notifier.toggleGroupSelection('grp_alpha');
        expect(container.read(provider).isMonitoring, isFalse);
        expect(container.read(provider).selectedGroupIds, isEmpty);

        notifier.toggleGroupSelection('grp_alpha');
        expect(container.read(provider).isMonitoring, isTrue);
      },
    );

    test(
      'toggleGroupSelection debounces refresh when adding a group while already monitoring',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );
        notifier.requestRefresh(immediate: false);

        final callsBefore = container.read(apiCallCounterProvider).totalCalls;

        notifier.toggleGroupSelection('grp_beta');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        expect(container.read(provider).selectedGroupIds, contains('grp_beta'));
        expect(
          container.read(apiCallCounterProvider).totalCalls,
          greaterThan(callsBefore),
        );
      },
    );

    test(
      'toggleGroupSelection does not immediately refresh on removal while still monitoring',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha', 'grp_beta'},
          isMonitoring: true,
        );
        notifier.requestRefresh(immediate: false);

        final callsBefore = container.read(apiCallCounterProvider).totalCalls;

        notifier.toggleGroupSelection('grp_beta');
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          container.read(provider).selectedGroupIds,
          isNot(contains('grp_beta')),
        );
        expect(container.read(provider).isMonitoring, isTrue);
        expect(container.read(apiCallCounterProvider).totalCalls, callsBefore);
      },
    );

    test(
      'toggleGroupSelection does not start monitoring for ineligible session',
      () {
        final harness = createGroupMonitorHarness(
          initialAuthState: unauthenticatedAuthState(),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState();

        notifier.toggleGroupSelection('grp_alpha');

        final currentState = container.read(provider);
        expect(currentState.selectedGroupIds, contains('grp_alpha'));
        expect(currentState.isMonitoring, isFalse);
      },
    );
  });

  group('baseline polling timer invariant', () {
    test(
      'creates a baseline polling timer when refresh is requested non-immediately',
      () {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );
        expect(notifier.hasActivePollingTimer, isFalse);

        notifier.requestRefresh(immediate: false);

        expect(notifier.hasActivePollingTimer, isTrue);
      },
    );

    test('forces monitoring off when active monitoring becomes ineligible', () {
      final harness = createGroupMonitorHarness(
        initialAuthState: unauthenticatedAuthState(),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      notifier.toggleGroupSelection('grp_beta');

      expect(container.read(provider).isMonitoring, isFalse);
      expect(notifier.hasActivePollingTimer, isFalse);
    });
  });

  group('rate limit and boost baseline behaviors', () {
    test(
      'baseline polling excludes boosted group to avoid duplicate calls',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        notifier.state = GroupMonitorState(
          selectedGroupIds: const {'grp_alpha'},
          isMonitoring: true,
          boostedGroupId: 'grp_alpha',
          boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
        );

        await notifier.fetchGroupInstances();
        notifier.stopMonitoring();

        expect(container.read(apiCallCounterProvider).totalCalls, 0);
      },
    );

    test('clearing boost triggers baseline recovery refresh', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = GroupMonitorState(
        selectedGroupIds: const {'grp_alpha'},
        isMonitoring: true,
        boostedGroupId: 'grp_alpha',
        boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      await notifier.clearBoost();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(apiCallCounterProvider).totalCalls, greaterThan(0));
    });

    test('automatic baseline poll is deferred during cooldown', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBaseline,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      await notifier.fetchGroupInstances();

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
      expect(container.read(apiCallCounterProvider).throttledSkips, 1);
      expect(container.read(provider).groupErrors, isEmpty);
    });

    test('automatic boost poll is deferred during cooldown', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBoost,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = GroupMonitorState(
        selectedGroupIds: const {'grp_alpha'},
        isMonitoring: true,
        boostedGroupId: 'grp_alpha',
        boostExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      await notifier.fetchBoostedGroupInstances();

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
      expect(container.read(apiCallCounterProvider).throttledSkips, 1);
      expect(container.read(provider).groupErrors, isEmpty);
    });

    test('manual refresh bypasses baseline cooldown', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBaseline,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      notifier.requestRefresh(immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(apiCallCounterProvider).totalCalls, greaterThan(0));
    });

    test(
      'queued manual refresh preserves bypass intent during cooldown',
      () async {
        final harness = createGroupMonitorHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        container
            .read(apiRateLimitCoordinatorProvider)
            .recordRateLimited(
              ApiRequestLane.groupBaseline,
              retryAfter: const Duration(seconds: 60),
            );

        notifier.state = const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
        );

        unawaited(notifier.fetchGroupInstances(bypassRateLimit: true));
        notifier.requestRefresh(immediate: true);
        await Future<void>.delayed(const Duration(milliseconds: 120));

        final baselineCalls =
            container
                .read(apiCallCounterProvider)
                .callsByLane['groupBaseline'] ??
            0;
        expect(baselineCalls, greaterThanOrEqualTo(2));
      },
    );

    test('records baseline diagnostics for cooldown skip', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.groupBaseline,
            retryAfter: const Duration(seconds: 60),
          );

      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      await notifier.fetchGroupInstances();

      final state = container.read(provider);
      expect(state.lastBaselineAttemptAt, isNotNull);
      expect(state.lastBaselineSuccessAt, isNull);
      expect(state.lastBaselineSkipReason, 'cooldown');
    });

    test('records baseline diagnostics for completed cycle', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = const GroupMonitorState(
        selectedGroupIds: {'grp_alpha'},
        isMonitoring: true,
      );

      await notifier.fetchGroupInstances(bypassRateLimit: true);

      final state = container.read(provider);
      expect(state.lastBaselineAttemptAt, isNotNull);
      expect(state.lastBaselineSuccessAt, isNotNull);
      expect(state.lastBaselinePolledGroupCount, 1);
      expect(state.lastBaselineTotalInstances, isNotNull);
      expect(state.lastBaselineSkipReason, isNull);
    });

    test('startMonitoring records a baseline attempt', () async {
      final harness = createGroupMonitorHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
      );
      final container = harness.container;
      final provider = harness.provider;
      final notifier = harness.notifier;
      addTearDown(container.dispose);
      notifier.state = const GroupMonitorState(selectedGroupIds: {'grp_alpha'});

      notifier.startMonitoring();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(provider).lastBaselineAttemptAt, isNotNull);
    });
  });

  group('setBoostedGroup', () {
    test(
      'emits one state update and resets boost diagnostics fields',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final provider = groupMonitorProvider('usr_test');
        final notifier = container.read(provider.notifier);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        notifier.state = GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
          isMonitoring: true,
          boostPollCount: 7,
          lastBoostLatencyMs: 150,
          lastBoostFetchedAt: DateTime.utc(2026, 2, 13, 10, 0),
          boostFirstSeenAfter: const Duration(seconds: 12),
        );

        final emittedStates = <GroupMonitorState>[];
        final subscription = container.listen<GroupMonitorState>(
          provider,
          (_, next) => emittedStates.add(next),
          fireImmediately: false,
        );

        await notifier.setBoostedGroup('grp_alpha');
        subscription.close();
        notifier.stopMonitoring();

        expect(emittedStates, hasLength(1));
        final updated = emittedStates.single;
        expect(updated.boostedGroupId, 'grp_alpha');
        expect(updated.boostExpiresAt, isNotNull);
        expect(updated.boostPollCount, 0);
        expect(updated.lastBoostLatencyMs, isNull);
        expect(updated.lastBoostFetchedAt, isNull);
        expect(updated.boostFirstSeenAfter, isNull);
      },
    );
  });
}
