import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/providers/group_monitor_api.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/portal_api_request_runner.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockVrchatRawApi extends Mock implements VrchatDartGenerated {}

class _MockWorldsApi extends Mock implements WorldsApi {}

class _MockWorld extends Mock implements World {}

void main() {
  test(
    'dedupes concurrent getWorld calls and tags world-details lane',
    () async {
      final api = _MockVrchatDart();
      final rawApi = _MockVrchatRawApi();
      final worldsApi = _MockWorldsApi();
      final world = _MockWorld();
      final recordedLanes = <ApiRequestLane?>[];
      final runner = PortalApiRequestRunner(
        coordinator: ApiRateLimitCoordinator(),
        recordApiCall: ({lane}) => recordedLanes.add(lane),
        recordThrottledSkip: ({lane}) {},
      );
      final monitorApi = VrchatGroupMonitorApi(api, runner);
      final completer = Completer<Response<World>>();

      when(() => api.rawApi).thenReturn(rawApi);
      when(() => rawApi.getWorldsApi()).thenReturn(worldsApi);
      when(
        () => worldsApi.getWorld(
          worldId: 'wrld_alpha',
          extra: any(named: 'extra'),
        ),
      ).thenAnswer((_) => completer.future);

      final first = monitorApi.getWorld(worldId: 'wrld_alpha');
      final second = monitorApi.getWorld(worldId: 'wrld_alpha');

      completer.complete(
        Response<World>(
          requestOptions: RequestOptions(path: '/worlds/wrld_alpha'),
          statusCode: 200,
          data: world,
        ),
      );

      expect((await first).data, same(world));
      expect((await second).data, same(world));
      expect(recordedLanes, [ApiRequestLane.worldDetails]);

      final extra =
          verify(
                () => worldsApi.getWorld(
                  worldId: 'wrld_alpha',
                  extra: captureAny(named: 'extra'),
                ),
              ).captured.single
              as Map<String, dynamic>?;
      expect(
        apiRequestLaneFromExtraValue(extra?[portalApiLaneExtraKey]),
        ApiRequestLane.worldDetails,
      );
    },
  );
}
