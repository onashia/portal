import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/portal_status_request_runner.dart';

void main() {
  group('PortalStatusRequestRunner', () {
    late ApiRateLimitCoordinator coordinator;
    late List<ApiRequestLane?> recordedCalls;
    late PortalStatusRequestRunner runner;

    setUp(() {
      coordinator = ApiRateLimitCoordinator();
      recordedCalls = <ApiRequestLane?>[];
      runner = PortalStatusRequestRunner(
        coordinator: coordinator,
        recordApiCall: ({lane}) => recordedCalls.add(lane),
        recordThrottledSkip: ({lane}) {},
      );
    });

    test('records API calls and passes lane metadata', () async {
      final result = await runner.run<String>(
        lane: ApiRequestLane.status,
        request: (extra) async =>
            apiRequestLaneFromExtraValue(extra?[portalApiLaneExtraKey])?.name ??
            'missing',
      );

      expect(result, 'status');
      expect(recordedCalls, [ApiRequestLane.status]);
    });

    test('records 429 cooldown from Dio errors', () async {
      await expectLater(
        runner.run<void>(
          lane: ApiRequestLane.status,
          request: (_) async {
            throw DioException(
              requestOptions: RequestOptions(path: '/summary.json'),
              response: Response<void>(
                requestOptions: RequestOptions(path: '/summary.json'),
                statusCode: 429,
                headers: Headers.fromMap(<String, List<String>>{
                  'retry-after': ['60'],
                }),
              ),
              type: DioExceptionType.badResponse,
            );
          },
        ),
        throwsA(isA<DioException>()),
      );

      expect(coordinator.remainingCooldown(ApiRequestLane.status), isNotNull);
    });

    test('successful requests do not create cooldown state', () async {
      final result = await runner.run<String>(
        lane: ApiRequestLane.status,
        request: (_) async => 'ok',
      );

      expect(result, 'ok');
      expect(coordinator.remainingCooldown(ApiRequestLane.status), isNull);
      expect(recordedCalls, [ApiRequestLane.status]);
    });
  });
}
