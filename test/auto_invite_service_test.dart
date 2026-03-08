import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/relay_hint_message.dart';
import 'package:portal/services/auto_invite_service.dart';
import 'package:portal/services/invite_service.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'test_helpers/fake_vrchat_models.dart';

class FakeInviteService implements InviteService {
  final List<Instance> invitedInstances = [];
  CancelToken? lastRetryCancelToken;
  String? lastRetryWorldId;
  String? lastRetryInstanceId;
  Duration? lastRetryWindow;

  @override
  Future<void> inviteSelfToInstance(Instance instance) async {
    invitedInstances.add(instance);
  }

  @override
  Future<void> inviteSelfToLocation({
    required String worldId,
    required String instanceId,
  }) async {}

  @override
  Future<InviteRetryOutcome> inviteSelfToLocationWithRetry({
    required String worldId,
    required String instanceId,
    Duration maxWindow = const Duration(seconds: 25),
    CancelToken? cancelToken,
  }) async {
    lastRetryWorldId = worldId;
    lastRetryInstanceId = instanceId;
    lastRetryWindow = maxWindow;
    lastRetryCancelToken = cancelToken;
    return InviteRetryOutcome.sent;
  }
}

class AlwaysFailingInviteService implements InviteService {
  @override
  Future<void> inviteSelfToInstance(Instance instance) async {
    throw Exception('Invite failed');
  }

  @override
  Future<void> inviteSelfToLocation({
    required String worldId,
    required String instanceId,
  }) async {
    throw Exception('Invite failed');
  }

  @override
  Future<InviteRetryOutcome> inviteSelfToLocationWithRetry({
    required String worldId,
    required String instanceId,
    Duration maxWindow = const Duration(seconds: 25),
    CancelToken? cancelToken,
  }) async {
    throw Exception('Invite failed');
  }
}

Instance _buildInviteableTestInstance({
  required String worldId,
  required String instanceId,
  required int userCount,
  required bool? canRequestInvite,
  bool? hasCapacityForYou,
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
    queueEnabled: false,
    queueSize: 0,
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

void main() {
  group('AutoInviteService.attemptAutoInvite', () {
    late FakeInviteService fakeInviteService;
    late AutoInviteService autoInviteService;

    setUp(() {
      fakeInviteService = FakeInviteService();
      autoInviteService = AutoInviteService(fakeInviteService);
    });

    test('returns null when disabled', () async {
      final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
      final instances = [
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: false,
        hasBaseline: true,
      );

      expect(result, isNull);
      expect(fakeInviteService.invitedInstances, isEmpty);
    });

    test('returns null when instances empty', () async {
      final result = await autoInviteService.attemptAutoInvite(
        instances: [],
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: true,
      );

      expect(result, isNull);
      expect(fakeInviteService.invitedInstances, isEmpty);
    });

    test('returns null when no baseline', () async {
      final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
      final instances = [
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: false,
      );

      expect(result, isNull);
      expect(fakeInviteService.invitedInstances, isEmpty);
    });

    test('selects instance with most users', () async {
      final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
      final instances = [
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 3),
        buildTestInstance(instanceId: 'inst_b', world: world, userCount: 8),
        buildTestInstance(instanceId: 'inst_c', world: world, userCount: 5),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: true,
      );

      expect(result, isNotNull);
      expect(result!.target.instance.instanceId, 'inst_b');
      expect(result.target.instance.nUsers, 8);
      expect(fakeInviteService.invitedInstances.length, 1);
      expect(fakeInviteService.invitedInstances[0].instanceId, 'inst_b');
    });

    test('tracks latency correctly', () async {
      final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
      final instances = [
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: true,
      );

      expect(result, isNotNull);
      expect(result!.latencyMs, greaterThanOrEqualTo(0));
      expect(result.latencyMs, lessThan(1000));
    });

    test(
      'does not block on canRequestInvite false when ids are valid',
      () async {
        final instances = [
          _buildInviteableTestInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
            canRequestInvite: false,
          ),
          _buildInviteableTestInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 8,
            canRequestInvite: true,
          ),
        ];

        final result = await autoInviteService.attemptAutoInvite(
          instances: instances,
          groupId: 'grp_alpha',
          enabled: true,
          hasBaseline: true,
        );

        expect(result, isNotNull);
        expect(result!.target.instance.instanceId, 'inst_a');
        expect(fakeInviteService.invitedInstances.single.instanceId, 'inst_a');
      },
    );

    test(
      'skips invalid top-population candidate and invites next eligible instance',
      () async {
        final instances = [
          _buildInviteableTestInstance(
            worldId: '',
            instanceId: 'inst_a',
            userCount: 10,
            canRequestInvite: true,
          ),
          _buildInviteableTestInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 8,
            canRequestInvite: true,
          ),
        ];

        final result = await autoInviteService.attemptAutoInvite(
          instances: instances,
          groupId: 'grp_alpha',
          enabled: true,
          hasBaseline: true,
        );

        expect(result, isNotNull);
        expect(result!.target.instance.instanceId, 'inst_b');
        expect(fakeInviteService.invitedInstances.single.instanceId, 'inst_b');
      },
    );

    test('treats null canRequestInvite as eligible', () async {
      final instances = [
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          userCount: 10,
          canRequestInvite: null,
        ),
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_b',
          userCount: 8,
          canRequestInvite: true,
        ),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: true,
      );

      expect(result, isNotNull);
      expect(result!.target.instance.instanceId, 'inst_a');
      expect(fakeInviteService.invitedInstances.single.instanceId, 'inst_a');
    });

    test('returns null when all candidates have invalid identifiers', () async {
      final instances = [
        _buildInviteableTestInstance(
          worldId: '',
          instanceId: 'inst_a',
          userCount: 10,
          canRequestInvite: false,
        ),
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: '',
          userCount: 8,
          canRequestInvite: false,
        ),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: true,
      );

      expect(result, isNull);
      expect(fakeInviteService.invitedInstances, isEmpty);
    });

    test('deprioritizes candidates with hasCapacityForYou false', () async {
      final instances = [
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          userCount: 10,
          canRequestInvite: false,
          hasCapacityForYou: false,
        ),
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_b',
          userCount: 9,
          canRequestInvite: true,
          hasCapacityForYou: true,
        ),
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_c',
          userCount: 8,
          canRequestInvite: true,
          hasCapacityForYou: true,
        ),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: true,
      );

      expect(result, isNotNull);
      expect(result!.target.instance.instanceId, 'inst_b');
      expect(fakeInviteService.invitedInstances.single.instanceId, 'inst_b');
    });

    test(
      'uses best valid-id candidate when all candidates report hasCapacityForYou false',
      () async {
        final instances = [
          _buildInviteableTestInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            userCount: 10,
            canRequestInvite: false,
            hasCapacityForYou: false,
          ),
          _buildInviteableTestInstance(
            worldId: 'wrld_alpha',
            instanceId: 'inst_b',
            userCount: 8,
            canRequestInvite: true,
            hasCapacityForYou: false,
          ),
        ];

        final result = await autoInviteService.attemptAutoInvite(
          instances: instances,
          groupId: 'grp_alpha',
          enabled: true,
          hasBaseline: true,
        );

        expect(result, isNotNull);
        expect(result!.target.instance.instanceId, 'inst_a');
        expect(fakeInviteService.invitedInstances.single.instanceId, 'inst_a');
      },
    );

    test('preserves highest-priority valid candidate ordering', () async {
      final instances = [
        _buildInviteableTestInstance(
          worldId: '',
          instanceId: 'inst_invalid',
          userCount: 12,
          canRequestInvite: true,
        ),
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          userCount: 10,
          canRequestInvite: false,
          hasCapacityForYou: false,
        ),
        _buildInviteableTestInstance(
          worldId: 'wrld_alpha',
          instanceId: 'inst_b',
          userCount: 9,
          canRequestInvite: true,
          hasCapacityForYou: true,
        ),
      ];

      final result = await autoInviteService.attemptAutoInvite(
        instances: instances,
        groupId: 'grp_alpha',
        enabled: true,
        hasBaseline: true,
      );

      expect(result, isNotNull);
      expect(result!.target.instance.instanceId, 'inst_b');
      expect(fakeInviteService.invitedInstances.single.instanceId, 'inst_b');
    });

    test('propagates invite service errors', () async {
      autoInviteService = AutoInviteService(AlwaysFailingInviteService());
      final world = buildTestWorld(id: 'wrld_alpha', name: 'World Alpha');
      final instances = [
        buildTestInstance(instanceId: 'inst_a', world: world, userCount: 5),
      ];

      expect(
        () => autoInviteService.attemptAutoInvite(
          instances: instances,
          groupId: 'grp_alpha',
          enabled: true,
          hasBaseline: true,
        ),
        throwsException,
      );
    });
  });

  group('AutoInviteService.attemptAutoInviteFromHint', () {
    late FakeInviteService fakeInviteService;
    late AutoInviteService autoInviteService;

    setUp(() {
      fakeInviteService = FakeInviteService();
      autoInviteService = AutoInviteService(fakeInviteService);
    });

    test('forwards cancel token and hint target to InviteService', () async {
      final cancelToken = CancelToken();
      final hint = RelayHintMessage.create(
        groupId: 'grp_11111111-1111-1111-1111-111111111111',
        worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
        instanceId: '12345~inst_a',
        nUsers: 6,
        sourceClientId: 'client_a',
        now: DateTime.now(),
      );

      final outcome = await autoInviteService.attemptAutoInviteFromHint(
        hint: hint,
        enabled: true,
        maxRetryWindow: const Duration(seconds: 7),
        cancelToken: cancelToken,
      );

      expect(outcome, InviteRetryOutcome.sent);
      expect(fakeInviteService.lastRetryWorldId, hint.worldId);
      expect(fakeInviteService.lastRetryInstanceId, hint.instanceId);
      expect(fakeInviteService.lastRetryWindow, const Duration(seconds: 7));
      expect(fakeInviteService.lastRetryCancelToken, same(cancelToken));
    });
  });
}
