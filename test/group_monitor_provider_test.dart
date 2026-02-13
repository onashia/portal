import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/group_monitor_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'test_helpers/fake_vrchat_models.dart';

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

  group('mergeFetchedGroupInstancesWithDiffForTesting', () {
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

        final merged = mergeFetchedGroupInstancesWithDiffForTesting(
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

        final merged = mergeFetchedGroupInstancesWithDiffForTesting(
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

      final merged = mergeFetchedGroupInstancesWithDiffForTesting(
        groupId: 'grp_alpha',
        fetchedInstances: fetchedInstances,
        previousInstances: previousInstances,
        detectedAt: detectedAt,
      );

      expect(merged.didChange, isTrue);
      expect(merged.newInstances, isEmpty);
      expect(identical(merged.effectiveInstances, previousInstances), isFalse);
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
        final resolvedAlpha = resolveGroupInstancesForGroup(
          previousInstances: previousAlpha,
          mergedInstances: [previousAlpha.first],
        );
        final resolvedBeta = resolveGroupInstancesForGroup(
          previousInstances: previousBeta,
          mergedInstances: [previousBeta.first],
        );
        didInstancesChange =
            didInstancesChange ||
            resolvedAlpha.didChange ||
            resolvedBeta.didChange;

        final nextGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': resolvedAlpha.effectiveInstances,
          'grp_beta': resolvedBeta.effectiveInstances,
        };
        final selectedGroupInstances = selectGroupInstancesForState(
          didInstancesChange: didInstancesChange,
          previousGroupInstances: previousGroupInstances,
          nextGroupInstances: nextGroupInstances,
        );

        expect(didInstancesChange, isFalse);
        expect(
          identical(resolvedAlpha.effectiveInstances, previousAlpha),
          isTrue,
        );
        expect(
          identical(resolvedBeta.effectiveInstances, previousBeta),
          isTrue,
        );
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
        final resolvedAlpha = resolveGroupInstancesForGroup(
          previousInstances: previousAlpha,
          mergedInstances: [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_alpha',
                world: world,
                userCount: 8,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: detectedAt,
            ),
          ],
        );
        final resolvedBeta = resolveGroupInstancesForGroup(
          previousInstances: previousBeta,
          mergedInstances: [previousBeta.first],
        );
        didInstancesChange =
            didInstancesChange ||
            resolvedAlpha.didChange ||
            resolvedBeta.didChange;

        final nextGroupInstances = <String, List<GroupInstanceWithGroup>>{
          'grp_alpha': resolvedAlpha.effectiveInstances,
          'grp_beta': resolvedBeta.effectiveInstances,
        };
        final selectedGroupInstances = selectGroupInstancesForState(
          didInstancesChange: didInstancesChange,
          previousGroupInstances: previousGroupInstances,
          nextGroupInstances: nextGroupInstances,
        );

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

  group('pending boost poll decisions', () {
    test(
      'queues pending boost poll only when boost is active and fetching',
      () {
        expect(
          shouldQueuePendingBoostPoll(
            isFetching: true,
            isMonitoring: true,
            isBoostActive: true,
          ),
          isTrue,
        );
        expect(
          shouldQueuePendingBoostPoll(
            isFetching: false,
            isMonitoring: true,
            isBoostActive: true,
          ),
          isFalse,
        );
        expect(
          shouldQueuePendingBoostPoll(
            isFetching: true,
            isMonitoring: false,
            isBoostActive: true,
          ),
          isFalse,
        );
        expect(
          shouldQueuePendingBoostPoll(
            isFetching: true,
            isMonitoring: true,
            isBoostActive: false,
          ),
          isFalse,
        );
      },
    );

    test('drains only when pending and not currently fetching', () {
      expect(
        shouldDrainPendingBoostPoll(
          pendingBoostPoll: true,
          isMonitoring: true,
          isBoostActive: true,
          isFetching: false,
        ),
        isTrue,
      );
      expect(
        shouldDrainPendingBoostPoll(
          pendingBoostPoll: true,
          isMonitoring: true,
          isBoostActive: true,
          isFetching: true,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingBoostPoll(
          pendingBoostPoll: true,
          isMonitoring: true,
          isBoostActive: false,
          isFetching: false,
        ),
        isFalse,
      );
      expect(
        shouldDrainPendingBoostPoll(
          pendingBoostPoll: false,
          isMonitoring: true,
          isBoostActive: true,
          isFetching: false,
        ),
        isFalse,
      );
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
