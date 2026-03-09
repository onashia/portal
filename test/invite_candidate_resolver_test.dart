import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/providers/group_instance_normalization.dart';
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

void main() {
  group('InviteCandidateResolver.resolveBestAutoInviteTarget', () {
    late InviteCandidateResolver resolver;
    late List<ApiRequestLane> observedLanes;

    setUp(() {
      resolver = InviteCandidateResolver();
      observedLanes = <ApiRequestLane>[];
    });

    test('picks first verified eligible candidate by discovery size', () async {
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

      final resolved = await resolver.resolveBestAutoInviteTarget(
        api: api,
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
        groupId: 'grp_alpha',
        lane: ApiRequestLane.groupBoost,
        laneLabel: 'boost',
        onApiCall: observedLanes.add,
      );

      expect(resolved, isNotNull);
      expect(resolved!.effectiveInstance.instanceId, 'inst_a');
      expect(
        resolved.verificationState,
        InviteCandidateVerificationState.verifiedEligible,
      );
      expect(observedLanes, [ApiRequestLane.groupBoost]);
    });

    test(
      'treats queueEnabled without queue entries as still inviteable',
      () async {
        final api = FakeGroupMonitorApi(
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
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
          discoveryInstances: [
            _buildDiscoveryInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_a',
              userCount: 10,
            ),
          ],
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_a');
        expect(resolved.effectiveInstance.queueEnabled, isTrue);
        expect(resolved.effectiveInstance.queueSize, 0);
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.verifiedEligible,
        );
      },
    );

    test('falls back to the next verified eligible candidate', () async {
      final api = FakeGroupMonitorApi(
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
      );

      final resolved = await resolver.resolveBestAutoInviteTarget(
        api: api,
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
        groupId: 'grp_alpha',
        lane: ApiRequestLane.groupBoost,
        laneLabel: 'boost',
      );

      expect(resolved, isNotNull);
      expect(resolved!.effectiveInstance.instanceId, 'inst_b');
      expect(
        resolved.verificationState,
        InviteCandidateVerificationState.verifiedEligible,
      );
      expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
      expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')], 1);
    });

    test('can fall through multiple full or queued candidates', () async {
      final api = FakeGroupMonitorApi(
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
            queueEnabled: true,
            queueSize: 2,
          ),
          _key('wrld_alpha', 'inst_c'): _buildEnrichedInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_c',
            userCount: 8,
            hasCapacityForYou: true,
          ),
        },
      );

      final resolved = await resolver.resolveBestAutoInviteTarget(
        api: api,
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
        groupId: 'grp_alpha',
        lane: ApiRequestLane.groupBoost,
        laneLabel: 'boost',
      );

      expect(resolved, isNotNull);
      expect(resolved!.effectiveInstance.instanceId, 'inst_c');
      expect(
        resolved.verificationState,
        InviteCandidateVerificationState.verifiedEligible,
      );
    });

    test(
      'falls back to current unresolved candidate when cap is reached',
      () async {
        final api = FakeGroupMonitorApi(
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
              queueEnabled: true,
              queueSize: 1,
            ),
            _key('wrld_alpha', 'inst_c'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_c',
              userCount: 8,
              hasCapacityForYou: false,
            ),
            _key('wrld_alpha', 'inst_d'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_d',
              userCount: 7,
              hasCapacityForYou: true,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
            _buildDiscoveryInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_d',
              userCount: 7,
            ),
          ],
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify: 3,
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_d');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.unresolvedFallback,
        );
        expect(
          api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_d')],
          isNull,
        );
      },
    );

    test(
      'skips cached full candidate when cap is reached and falls back later',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_a',
              userCount: 10,
              hasCapacityForYou: false,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
              hasCapacityForYou: false,
            ),
            _buildDiscoveryInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_c',
              userCount: 8,
            ),
          ],
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify: 1,
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_c');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.unresolvedFallback,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(
          api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')],
          isNull,
        );
        expect(
          api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_c')],
          isNull,
        );
      },
    );

    test(
      'skips cached queued candidate when cap is reached and returns null',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_a',
              userCount: 10,
              hasCapacityForYou: false,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
              hasCapacityForYou: true,
              queueEnabled: true,
              queueSize: 2,
            ),
          ],
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify: 1,
        );

        expect(resolved, isNull);
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(
          api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')],
          isNull,
        );
      },
    );

    test(
      'falls back to current unresolved candidate when later verification is unavailable',
      () async {
        final api = FakeGroupMonitorApi(
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
              hasCapacityForYou: false,
            ),
          },
          instanceErrorsByKey: {
            _key('wrld_alpha', 'inst_c'): DioException(
              requestOptions: RequestOptions(
                path: '/instances/wrld_alpha:inst_c',
              ),
              response: Response<void>(
                requestOptions: RequestOptions(
                  path: '/instances/wrld_alpha:inst_c',
                ),
                statusCode: 429,
              ),
              type: DioExceptionType.badResponse,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_c');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.unresolvedFallback,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')], 1);
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_c')], 1);
      },
    );

    test(
      'returns null when all verified candidates are full or queued',
      () async {
        final api = FakeGroupMonitorApi(
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
              queueEnabled: true,
              queueSize: 3,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNull);
      },
    );

    test(
      'treats canRequestInvite false as advisory when capacity is valid',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_a'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_a',
              userCount: 10,
              canRequestInvite: false,
              hasCapacityForYou: true,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
          discoveryInstances: [
            _buildDiscoveryInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_a',
              userCount: 10,
            ),
          ],
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_a');
        expect(resolved.effectiveInstance.canRequestInvite, isFalse);
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.verifiedEligible,
        );
      },
    );

    test(
      'uses current unresolved fallback after cap is exhausted by proven-bad candidate',
      () async {
        final api = FakeGroupMonitorApi(
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
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify: 1,
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_b');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.unresolvedFallback,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(
          api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')],
          isNull,
        );
      },
    );

    test(
      'skips a 404 candidate and selects the next verified candidate',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_b',
              userCount: 9,
              hasCapacityForYou: true,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_b');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.verifiedEligible,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')], 1);
      },
    );

    test(
      'skips an empty response candidate and selects the next verified candidate',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_b',
              userCount: 9,
              hasCapacityForYou: true,
            ),
          },
          nullInstanceResponseKeys: {_key('wrld_alpha', 'inst_a')},
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_b');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.verifiedEligible,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')], 1);
      },
    );

    test(
      'does not let an invalid candidate exhaust the verification cap',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_b',
              userCount: 9,
              hasCapacityForYou: true,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify: 1,
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_b');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.verifiedEligible,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')], 1);
      },
    );

    test(
      'falls back to current candidate when first verification is transiently unavailable',
      () async {
        final api = FakeGroupMonitorApi(
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
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_a');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.unresolvedFallback,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(
          api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')],
          isNull,
        );
      },
    );

    test(
      'falls back to current candidate when first verification hits a server error',
      () async {
        final api = FakeGroupMonitorApi(
          instanceErrorsByKey: {
            _key('wrld_alpha', 'inst_a'): DioException(
              requestOptions: RequestOptions(
                path: '/instances/wrld_alpha:inst_a',
              ),
              response: Response<void>(
                requestOptions: RequestOptions(
                  path: '/instances/wrld_alpha:inst_a',
                ),
                statusCode: 503,
              ),
              type: DioExceptionType.badResponse,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_a');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.unresolvedFallback,
        );
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
        expect(
          api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')],
          isNull,
        );
      },
    );

    test(
      'skips invalid identifiers before selecting a verified candidate',
      () async {
        final api = FakeGroupMonitorApi(
          enrichedInstancesByKey: {
            _key('wrld_alpha', 'inst_b'): _buildEnrichedInstance(
              worldId: 'wrld_alpha',
              instanceId: 'inst_b',
              userCount: 9,
              hasCapacityForYou: true,
            ),
          },
        );

        final resolved = await resolver.resolveBestAutoInviteTarget(
          api: api,
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
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
        );

        expect(resolved, isNotNull);
        expect(resolved!.effectiveInstance.instanceId, 'inst_b');
        expect(
          resolved.verificationState,
          InviteCandidateVerificationState.verifiedEligible,
        );
        expect(api.getInstanceCallCountByKey[_key('', 'inst_a')], isNull);
        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_b')], 1);
      },
    );

    test('returns null when every candidate has invalid identifiers', () async {
      final api = FakeGroupMonitorApi();

      final resolved = await resolver.resolveBestAutoInviteTarget(
        api: api,
        discoveryInstances: [
          _buildDiscoveryInstance(
            worldId: '',
            instanceId: 'inst_a',
            userCount: 10,
          ),
          _buildDiscoveryInstance(
            worldId: 'wrld_alpha',
            instanceId: '',
            userCount: 9,
          ),
        ],
        groupId: 'grp_alpha',
        lane: ApiRequestLane.groupBoost,
        laneLabel: 'boost',
      );

      expect(resolved, isNull);
    });
  });

  group(
    'InviteCandidateResolver.enrichHighestPopulationInstanceForDisplay',
    () {
      test(
        'only applies verified negative metadata to the enriched candidate',
        () async {
          final resolver = InviteCandidateResolver();
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
          final discoveryInstances = [
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
          ];

          final effective = await resolver
              .enrichHighestPopulationInstanceForDisplay(
                api: api,
                discoveryInstances: discoveryInstances,
                groupId: 'grp_alpha',
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

      test('reuses cached enrichment across repeated resolutions', () async {
        final resolver = InviteCandidateResolver();
        final world = buildTestWorld(id: 'wrld_alpha', name: 'World');
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
        final discoveryInstance = normalizeGroupInstance(
          groupInstance: buildTestGroupInstance(
            instanceId: 'inst_a',
            world: world,
            memberCount: 10,
          ),
          groupId: 'grp_alpha',
        );

        await resolver.resolveBestAutoInviteTarget(
          api: api,
          discoveryInstances: [discoveryInstance],
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify:
              AppConstants.groupInstanceInviteVerificationMaxCandidates,
        );
        await resolver.resolveBestAutoInviteTarget(
          api: api,
          discoveryInstances: [discoveryInstance],
          groupId: 'grp_alpha',
          lane: ApiRequestLane.groupBoost,
          laneLabel: 'boost',
          maxCandidatesToVerify:
              AppConstants.groupInstanceInviteVerificationMaxCandidates,
        );

        expect(api.getInstanceCallCountByKey[_key('wrld_alpha', 'inst_a')], 1);
      });
    },
  );
}
