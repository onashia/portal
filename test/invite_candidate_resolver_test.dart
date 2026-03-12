import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/invite_candidate_resolver.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;

import 'test_helpers/fake_group_monitor_api.dart';
import 'test_helpers/fake_vrchat_models.dart';

Instance _buildDiscoveryInstance({
  required String worldId,
  required String instanceId,
  required int userCount,
  bool? canRequestInvite,
  bool? hasCapacityForYou,
  bool queueEnabled = false,
  int queueSize = 0,
}) {
  final world = buildTestWorld(
    id: worldId.isEmpty ? 'wrld_fallback' : worldId,
    name: 'World',
  );
  return Instance(
    canRequestInvite: canRequestInvite,
    clientNumber: 'unknown',
    hasCapacityForYou: hasCapacityForYou,
    id: 'inst_${instanceId.isEmpty ? 'fallback' : instanceId}',
    instanceId: instanceId,
    location: '$worldId:$instanceId',
    nUsers: userCount,
    name: 'Instance $instanceId',
    photonRegion: Region.us,
    platforms: InstancePlatforms(android: 0, standalonewindows: userCount),
    queueEnabled: queueEnabled,
    queueSize: queueSize,
    recommendedCapacity: 16,
    region: InstanceRegion.us,
    secureName: 'secure-${instanceId.isEmpty ? 'fallback' : instanceId}',
    strict: false,
    tags: const [],
    type: InstanceType.group,
    userCount: userCount,
    world: world,
    worldId: worldId,
  );
}

Instance _buildEnrichedInstance({
  required String worldId,
  required String instanceId,
  required int userCount,
  bool? canRequestInvite,
  bool? hasCapacityForYou,
  bool queueEnabled = false,
  int queueSize = 0,
}) {
  final world = buildTestWorld(id: worldId, name: 'World');
  return Instance(
    canRequestInvite: canRequestInvite,
    clientNumber: 'unknown',
    hasCapacityForYou: hasCapacityForYou,
    id: 'inst_$instanceId',
    instanceId: instanceId,
    location: '$worldId:$instanceId',
    nUsers: userCount,
    name: 'Instance $instanceId',
    photonRegion: Region.us,
    platforms: InstancePlatforms(android: 0, standalonewindows: userCount),
    queueEnabled: queueEnabled,
    queueSize: queueSize,
    recommendedCapacity: 16,
    region: InstanceRegion.us,
    secureName: 'secure-$instanceId',
    strict: false,
    tags: const [],
    type: InstanceType.group,
    userCount: userCount,
    world: world,
    worldId: worldId,
  );
}

String _key(String worldId, String instanceId) => '$worldId|$instanceId';

InviteCandidateResolver _buildResolver(
  FakeGroupMonitorApi api, {
  List<ApiRequestLane>? observedLanes,
}) {
  return InviteCandidateResolver(
    fetchInstance:
        ({
          required String worldId,
          required String instanceId,
          required ApiRequestLane lane,
        }) {
          observedLanes?.add(lane);
          return api.getInstance(
            worldId: worldId,
            instanceId: instanceId,
            lane: lane,
          );
        },
  );
}

typedef _ResolverScenario = ({
  String description,
  List<Instance> discoveryInstances,
  Map<String, Instance> enrichedInstancesByKey,
  Map<String, Object> instanceErrorsByKey,
  Set<String> nullInstanceResponseKeys,
  int maxCandidatesToVerify,
  String? expectedInstanceId,
  Map<String, int?> expectedCallCounts,
});

void main() {
  group('InviteCandidateResolver.resolveBestAutoInviteTarget', () {
    final scenarios = <_ResolverScenario>[
      (
        description: 'picks first verified eligible candidate',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 8,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 3,
        expectedInstanceId: 'inst_a',
        expectedCallCounts: {_key('wrld_alpha', 'inst_a'): 1},
      ),
      (
        description:
            'skips invalid identifiers before selecting verified candidate',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: '',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 1,
        expectedInstanceId: 'inst_b',
        expectedCallCounts: {
          _key('', 'inst_a'): null,
          _key('wrld_alpha', 'inst_b'): 1,
        },
      ),
      (
        description: 'skips verified full candidate and falls through',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
            hasCapacityForYou: false,
          ),
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 3,
        expectedInstanceId: 'inst_b',
        expectedCallCounts: {
          _key('wrld_alpha', 'inst_a'): 1,
          _key('wrld_alpha', 'inst_b'): 1,
        },
      ),
      (
        description:
            'skips verified queued candidate when queue size is greater than zero',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
            hasCapacityForYou: true,
            queueEnabled: true,
            queueSize: 2,
          ),
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 3,
        expectedInstanceId: 'inst_b',
        expectedCallCounts: {
          _key('wrld_alpha', 'inst_a'): 1,
          _key('wrld_alpha', 'inst_b'): 1,
        },
      ),
      (
        description:
            'keeps queue-enabled candidate eligible when queue is empty',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
            hasCapacityForYou: true,
            queueEnabled: true,
            queueSize: 0,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 1,
        expectedInstanceId: 'inst_a',
        expectedCallCounts: {_key('wrld_alpha', 'inst_a'): 1},
      ),
      (
        description:
            'falls back to unresolved candidate on transient verification failure',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
        ],
        enrichedInstancesByKey: const {},
        instanceErrorsByKey: {
          _key('wrld_alpha', 'inst_a'): DioException(
            requestOptions: RequestOptions(
              path: '/instances/wrld_alpha:inst_a',
            ),
            response: Response<void>(
              requestOptions: RequestOptions(
                path: '/instances/wrld_alpha:inst_a',
              ),
              statusCode: 429,
            ),
            type: DioExceptionType.badResponse,
          ),
        },
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 3,
        expectedInstanceId: 'inst_a',
        expectedCallCounts: {
          _key('wrld_alpha', 'inst_a'): 1,
          _key('wrld_alpha', 'inst_b'): null,
        },
      ),
      (
        description:
            'skips a 404 candidate and selects the next verified candidate',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 3,
        expectedInstanceId: 'inst_b',
        expectedCallCounts: {
          _key('wrld_alpha', 'inst_a'): 1,
          _key('wrld_alpha', 'inst_b'): 1,
        },
      ),
      (
        description:
            'counts invalid verification attempts toward the verification cap',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 1,
        expectedInstanceId: 'inst_b',
        expectedCallCounts: {
          _key('wrld_alpha', 'inst_a'): 1,
          _key('wrld_alpha', 'inst_b'): null,
        },
      ),
      (
        description:
            'counts invalid and unavailable verifications before applying the cap',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_c',
            userCount: 8,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: false,
          ),
          _key('wrld_alpha', 'inst_c'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_c',
            userCount: 8,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 2,
        expectedInstanceId: 'inst_c',
        expectedCallCounts: {
          _key('wrld_alpha', 'inst_a'): 1,
          _key('wrld_alpha', 'inst_b'): 1,
          _key('wrld_alpha', 'inst_c'): null,
        },
      ),
      (
        description:
            'falls back to current unresolved candidate when verification cap is reached',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
            hasCapacityForYou: false,
          ),
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: true,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 1,
        expectedInstanceId: 'inst_b',
        expectedCallCounts: {
          _key('wrld_alpha', 'inst_a'): 1,
          _key('wrld_alpha', 'inst_b'): null,
        },
      ),
      (
        description:
            'returns null when all candidates are invalid or verified unavailable',
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: '',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_c',
            userCount: 8,
          ),
        ],
        enrichedInstancesByKey: {
          _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 9,
            hasCapacityForYou: false,
          ),
          _key('wrld_alpha', 'inst_c'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_c',
            userCount: 8,
            hasCapacityForYou: true,
            queueEnabled: true,
            queueSize: 3,
          ),
        },
        instanceErrorsByKey: const {},
        nullInstanceResponseKeys: const {},
        maxCandidatesToVerify: 3,
        expectedInstanceId: null,
        expectedCallCounts: {
          _key('', 'inst_a'): null,
          _key('wrld_alpha', 'inst_b'): 1,
          _key('wrld_alpha', 'inst_c'): 1,
        },
      ),
    ];

    for (final scenario in scenarios) {
      test(scenario.description, () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: scenario.enrichedInstancesByKey,
          instanceErrorsByKey: scenario.instanceErrorsByKey,
          nullInstanceResponseKeys: scenario.nullInstanceResponseKeys,
        );
        final observedLanes = <ApiRequestLane>[];
        final resolver = _buildResolver(api, observedLanes: observedLanes);

        final resolved = await resolver.resolveBestAutoInviteTarget(
          discoveryInstances: scenario.discoveryInstances,
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify: scenario.maxCandidatesToVerify,
        );

        expect(resolved?.instance.instanceId, scenario.expectedInstanceId);
        for (final expected in scenario.expectedCallCounts.entries) {
          expect(api.getInstanceCallCountByKey[expected.key], expected.value);
        }
        expect(observedLanes, everyElement(ApiRequestLane.groupBoost));
      });
    }
  });

  group('InviteCandidateResolver.normalizeAndEnrichFetchedGroupInstances', () {
    test(
      'applies verified metadata only to the highest-population candidate',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_a',
              userCount: 10,
              hasCapacityForYou: false,
              queueEnabled: true,
              queueSize: 3,
            ),
          },
        );
        final resolver = _buildResolver(api);
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World');

        final effective = await resolver
            .normalizeAndEnrichFetchedGroupInstances(
              groupInstances: [
                buildTestGroupInstance(
                  instanceId: 'inst_a',
                  world: world,
                  memberCount: 10,
                ),
                buildTestGroupInstance(
                  instanceId: 'inst_b',
                  world: world,
                  memberCount: 9,
                ),
              ],
              groupId: 'grp_alpha',
              retainedKeys: {
                _key('wrld_alpha', 'inst_a'),
                _key('wrld_alpha', 'inst_b'),
              },
              lane: ApiRequestLane.groupBoost,
              laneLabel: 'boost',
            );

        expect(effective[0].hasCapacityForYou, isFalse);
        expect(effective[0].queueEnabled, isTrue);
        expect(effective[0].queueSize, 3);
        expect(effective[1].hasCapacityForYou, isNull);
        expect(effective[1].queueEnabled, isFalse);
        expect(effective[1].queueSize, 0);
      },
    );

    test(
      'reuses cached enrichment across repeated fetch normalization',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_a',
              userCount: 10,
              hasCapacityForYou: true,
            ),
          },
        );
        final resolver = _buildResolver(api);
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World');
        final groupInstances = [
          buildTestGroupInstance(
            instanceId: 'inst_a',
            world: world,
            memberCount: 10,
          ),
        ];

        await resolver.normalizeAndEnrichFetchedGroupInstances(
          groupInstances: groupInstances,
          groupId: 'grp_alpha',
          retainedKeys: {_key('wrld_alpha', 'inst_a')},
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );
        await resolver.normalizeAndEnrichFetchedGroupInstances(
          groupInstances: groupInstances,
          groupId: 'grp_alpha',
          retainedKeys: {_key('wrld_alpha', 'inst_a')},
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
      },
    );

    test(
      'preserves transient failure cooldown for instances that briefly disappear',
      () async {
        final key = _key('wrld_alpha', 'inst_a');
        final api = FakeGroupMonitorApi(
          instanceErrorsByKey: {
            key: DioException(
              requestOptions: RequestOptions(
                path: '/instances/wrld_alpha:inst_a',
              ),
              response: Response<void>(
                requestOptions: RequestOptions(
                  path: '/instances/wrld_alpha:inst_a',
                ),
                statusCode: 429,
              ),
              type: DioExceptionType.badResponse,
            ),
          },
        );
        final resolver = _buildResolver(api);
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World');
        final groupInstances = [
          buildTestGroupInstance(
            instanceId: 'inst_a',
            world: world,
            memberCount: 10,
          ),
        ];

        await resolver.normalizeAndEnrichFetchedGroupInstances(
          groupInstances: groupInstances,
          groupId: 'grp_alpha',
          retainedKeys: {key},
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );
        expect(api.getInstanceCallCountByKey[key], 1);

        resolver.pruneState(DateTime.now(), retainedKeys: const {});

        api.instanceErrorsByKey.remove(key);
        api.enrichedInstancesByKey[key] = _buildEnrichedInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          userCount: 10,
          hasCapacityForYou: true,
        );

        await resolver.normalizeAndEnrichFetchedGroupInstances(
          groupInstances: groupInstances,
          groupId: 'grp_alpha',
          retainedKeys: {key},
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );
        expect(
          api.getInstanceCallCountByKey[key],
          1,
          reason: 'active cooldown should suppress re-fetch after reappearance',
        );

        resolver.pruneState(
          DateTime.now().add(
            const Duration(
              seconds:
                  AppConstants.groupInstanceEnrichmentFailureCooldownSeconds +
                  1,
            ),
          ),
          retainedKeys: const {},
        );

        await resolver.normalizeAndEnrichFetchedGroupInstances(
          groupInstances: groupInstances,
          groupId: 'grp_alpha',
          retainedKeys: {key},
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );
        expect(api.getInstanceCallCountByKey[key], 2);
      },
    );
  });
}
