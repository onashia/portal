import 'package:dio/dio.dart';
import 'package:portal/providers/group_monitor_api.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;

class FakeGroupMonitorApi implements GroupMonitorApi {
  FakeGroupMonitorApi({
    List<LimitedUserGroups>? userGroups,
    Map<String, List<GroupInstance>>? groupInstancesByGroupId,
    Map<String, Instance>? enrichedInstancesByKey,
    Map<String, World>? worldsById,
    this.userGroupsError,
    Map<String, Object>? groupInstancesErrorsByGroupId,
    Map<String, Object>? instanceErrorsByKey,
    Map<String, Object>? worldErrorsById,
  }) : userGroups = userGroups ?? <LimitedUserGroups>[],
       groupInstancesByGroupId =
           groupInstancesByGroupId ?? <String, List<GroupInstance>>{},
       enrichedInstancesByKey = enrichedInstancesByKey ?? <String, Instance>{},
       worldsById = worldsById ?? <String, World>{},
       groupInstancesErrorsByGroupId =
           groupInstancesErrorsByGroupId ?? <String, Object>{},
       instanceErrorsByKey = instanceErrorsByKey ?? <String, Object>{},
       worldErrorsById = worldErrorsById ?? <String, Object>{};

  final List<LimitedUserGroups> userGroups;
  final Map<String, List<GroupInstance>> groupInstancesByGroupId;
  final Map<String, Instance> enrichedInstancesByKey;
  final Map<String, World> worldsById;
  final Object? userGroupsError;
  final Map<String, Object> groupInstancesErrorsByGroupId;
  final Map<String, Object> instanceErrorsByKey;
  final Map<String, Object> worldErrorsById;

  int getUserGroupsCallCount = 0;
  final Map<String, int> getGroupInstancesCallCountByGroupId = <String, int>{};
  final Map<String, int> getInstanceCallCountByKey = <String, int>{};
  final Map<String, int> getWorldCallCountByWorldId = <String, int>{};

  @override
  Future<Response<List<GroupInstance>>> getGroupInstances({
    required String groupId,
    required ApiRequestLane lane,
  }) async {
    getGroupInstancesCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );

    final error = groupInstancesErrorsByGroupId[groupId];
    if (error != null) {
      throw error;
    }

    return _response<List<GroupInstance>>(
      groupInstancesByGroupId[groupId] ?? const <GroupInstance>[],
      path: '/groups/$groupId/instances',
    );
  }

  @override
  Future<Response<Instance>> getInstance({
    required String worldId,
    required String instanceId,
    required ApiRequestLane lane,
  }) async {
    final key = _instanceKey(worldId: worldId, instanceId: instanceId);
    getInstanceCallCountByKey.update(
      key,
      (count) => count + 1,
      ifAbsent: () {
        return 1;
      },
    );

    final error = instanceErrorsByKey[key];
    if (error != null) {
      throw error;
    }

    final instance = enrichedInstancesByKey[key];
    if (instance == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/instances/$worldId:$instanceId'),
        response: Response<void>(
          requestOptions: RequestOptions(
            path: '/instances/$worldId:$instanceId',
          ),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );
    }

    return _response<Instance>(
      instance,
      path: '/instances/$worldId:$instanceId',
    );
  }

  @override
  Future<Response<List<LimitedUserGroups>>> getUserGroups({
    required String userId,
  }) async {
    getUserGroupsCallCount += 1;
    if (userGroupsError != null) {
      throw userGroupsError!;
    }
    return _response<List<LimitedUserGroups>>(
      userGroups,
      path: '/users/$userId/groups',
    );
  }

  @override
  Future<Response<World>> getWorld({required String worldId}) async {
    getWorldCallCountByWorldId.update(
      worldId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );

    final error = worldErrorsById[worldId];
    if (error != null) {
      throw error;
    }

    final world = worldsById[worldId];
    if (world == null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/worlds/$worldId'),
        response: Response<void>(
          requestOptions: RequestOptions(path: '/worlds/$worldId'),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );
    }

    return _response<World>(world, path: '/worlds/$worldId');
  }

  Response<T> _response<T>(T data, {required String path}) {
    return Response<T>(
      data: data,
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      statusMessage: 'OK',
    );
  }

  String _instanceKey({required String worldId, required String instanceId}) {
    return '$worldId|$instanceId';
  }
}
