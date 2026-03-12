import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;

import '../services/api_rate_limit_coordinator.dart';
import 'auth_provider.dart';

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
  const VrchatGroupMonitorApi(this._api);

  final VrchatDart _api;

  @override
  Future<Response<List<LimitedUserGroups>>> getUserGroups({
    required String userId,
  }) {
    return _api.rawApi.getUsersApi().getUserGroups(
      userId: userId,
      extra: apiRequestLaneExtra(ApiRequestLane.userGroups),
    );
  }

  @override
  Future<Response<List<GroupInstance>>> getGroupInstances({
    required String groupId,
    required ApiRequestLane lane,
  }) {
    return _api.rawApi.getGroupsApi().getGroupInstances(
      groupId: groupId,
      extra: apiRequestLaneExtra(lane),
    );
  }

  @override
  Future<Response<Instance>> getInstance({
    required String worldId,
    required String instanceId,
    required ApiRequestLane lane,
  }) {
    return _api.rawApi.getInstancesApi().getInstance(
      worldId: worldId,
      instanceId: instanceId,
      extra: apiRequestLaneExtra(lane),
    );
  }

  @override
  Future<Response<World>> getWorld({required String worldId}) {
    return _api.rawApi.getWorldsApi().getWorld(worldId: worldId);
  }
}

final groupMonitorApiProvider = Provider<GroupMonitorApi>((ref) {
  return VrchatGroupMonitorApi(ref.read(vrchatApiProvider));
});
