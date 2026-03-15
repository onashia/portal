import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;

import 'auth_provider.dart';
import 'portal_api_request_runner_provider.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../services/portal_api_request_runner.dart';

abstract class GroupMonitorApi {
  Future<Response<List<LimitedUserGroups>>> getUserGroups({
    required String userId,
  });

  Future<Response<List<GroupInstance>>> getGroupInstances({
    required String groupId,
    required ApiRequestLane lane,
  });

  Future<Response<Instance>> getInstance({
    required String worldId,
    required String instanceId,
    required ApiRequestLane lane,
  });

  Future<Response<World>> getWorld({required String worldId});
}

class VrchatGroupMonitorApi implements GroupMonitorApi {
  const VrchatGroupMonitorApi(this._api, this._runner);

  final VrchatDart _api;
  final PortalApiRequestRunner _runner;

  @override
  Future<Response<List<LimitedUserGroups>>> getUserGroups({
    required String userId,
  }) {
    return _runner.run(
      lane: ApiRequestLane.userGroups,
      request: (extra) =>
          _api.rawApi.getUsersApi().getUserGroups(userId: userId, extra: extra),
    );
  }

  @override
  Future<Response<List<GroupInstance>>> getGroupInstances({
    required String groupId,
    required ApiRequestLane lane,
  }) {
    return _runner.run(
      lane: lane,
      request: (extra) => _api.rawApi.getGroupsApi().getGroupInstances(
        groupId: groupId,
        extra: extra,
      ),
    );
  }

  @override
  Future<Response<Instance>> getInstance({
    required String worldId,
    required String instanceId,
    required ApiRequestLane lane,
  }) {
    return _runner.run(
      lane: lane,
      request: (extra) => _api.rawApi.getInstancesApi().getInstance(
        worldId: worldId,
        instanceId: instanceId,
        extra: extra,
      ),
    );
  }

  @override
  Future<Response<World>> getWorld({required String worldId}) {
    return _runner.runWithReadDedupe(
      dedupeKey: 'world|$worldId',
      lane: ApiRequestLane.worldDetails,
      request: (extra) =>
          _api.rawApi.getWorldsApi().getWorld(worldId: worldId, extra: extra),
    );
  }
}

final groupMonitorApiProvider = Provider<GroupMonitorApi>((ref) {
  return VrchatGroupMonitorApi(
    ref.read(vrchatApiProvider),
    ref.read(portalApiRequestRunnerProvider),
  );
});
