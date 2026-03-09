import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/group_instance_with_group.dart';
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

GroupInstanceWithGroup _buildInviteTarget({
  required String groupId,
  required String worldId,
  required String instanceId,
  required int userCount,
}) {
  final world = buildTestWorld(id: worldId, name: 'World');
  return GroupInstanceWithGroup(
    groupId: groupId,
    instance: buildTestInstance(
      instanceId: instanceId,
      world: world,
      userCount: userCount,
    ),
  );
}

void main() {
  group('AutoInviteService.attemptAutoInviteTarget', () {
    late FakeInviteService fakeInviteService;
    late AutoInviteService autoInviteService;
    late GroupInstanceWithGroup target;

    setUp(() {
      fakeInviteService = FakeInviteService();
      autoInviteService = AutoInviteService(fakeInviteService);
      target = _buildInviteTarget(
        groupId: 'grp_alpha',
        worldId: 'wrld_alpha',
        instanceId: 'inst_a',
        userCount: 5,
      );
    });

    test('returns early when disabled', () async {
      await autoInviteService.attemptAutoInviteTarget(
        target: target,
        enabled: false,
        hasBaseline: true,
      );

      expect(fakeInviteService.invitedInstances, isEmpty);
    });

    test('returns early when no baseline', () async {
      await autoInviteService.attemptAutoInviteTarget(
        target: target,
        enabled: true,
        hasBaseline: false,
      );

      expect(fakeInviteService.invitedInstances, isEmpty);
    });

    test('sends invite to resolved target', () async {
      await autoInviteService.attemptAutoInviteTarget(
        target: target,
        enabled: true,
        hasBaseline: true,
      );

      expect(fakeInviteService.invitedInstances.single.instanceId, 'inst_a');
    });

    test('propagates invite service errors', () async {
      autoInviteService = AutoInviteService(AlwaysFailingInviteService());

      expect(
        () => autoInviteService.attemptAutoInviteTarget(
          target: target,
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
