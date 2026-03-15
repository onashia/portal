import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/portal_api_request_runner.dart';

void main() {
  group('PortalApiRequestRunner', () {
    late ApiRateLimitCoordinator coordinator;
    late List<ApiRequestLane?> recordedCalls;
    late List<ApiRequestLane?> recordedSkips;
    late PortalApiRequestRunner runner;

    setUp(() {
      coordinator = ApiRateLimitCoordinator();
      recordedCalls = <ApiRequestLane?>[];
      recordedSkips = <ApiRequestLane?>[];
      runner = PortalApiRequestRunner(
        coordinator: coordinator,
        recordApiCall: ({lane}) => recordedCalls.add(lane),
        recordThrottledSkip: ({lane}) => recordedSkips.add(lane),
      );
    });

    test('records API calls and passes lane metadata', () async {
      final result = await runner.run<String>(
        lane: ApiRequestLane.calendar,
        request: (extra) async =>
            apiRequestLaneFromExtraValue(extra?[portalApiLaneExtraKey])?.name ??
            'missing',
      );

      expect(result, 'calendar');
      expect(recordedCalls, [ApiRequestLane.calendar]);
    });

    test('records throttled skip when cooldown is active', () {
      coordinator.recordRateLimited(ApiRequestLane.groupBaseline);

      final deferred = runner.shouldDeferForCooldown(
        lane: ApiRequestLane.groupBaseline,
        bypassRateLimit: false,
      );

      expect(deferred, isTrue);
      expect(recordedSkips, [ApiRequestLane.groupBaseline]);
    });

    test('manual bypass ignores cooldown', () {
      coordinator.recordRateLimited(ApiRequestLane.groupBaseline);

      final deferred = runner.shouldDeferForCooldown(
        lane: ApiRequestLane.groupBaseline,
        bypassRateLimit: true,
      );

      expect(deferred, isFalse);
      expect(recordedSkips, isEmpty);
    });

    test('records 429 cooldown from Dio errors', () async {
      await expectLater(
        runner.run<void>(
          lane: ApiRequestLane.image,
          request: (_) async {
            throw DioException(
              requestOptions: RequestOptions(path: '/files/file_1/1'),
              response: Response<void>(
                requestOptions: RequestOptions(path: '/files/file_1/1'),
                statusCode: 429,
                headers: Headers.fromMap(<String, List<String>>{
                  'retry-after': ['15'],
                }),
              ),
              type: DioExceptionType.badResponse,
            );
          },
        ),
        throwsA(isA<DioException>()),
      );

      expect(coordinator.remainingCooldown(ApiRequestLane.image), isNotNull);
    });

    test('dedupes concurrent read requests by key and cleans up in-flight state', () async {
      final completer = Completer<String>();
      var executions = 0;

      final first = runner.runWithReadDedupe<String>(
        dedupeKey: 'world|wrld_alpha',
        lane: ApiRequestLane.worldDetails,
        request: (_) async {
          executions += 1;
          return completer.future;
        },
      );
      final second = runner.runWithReadDedupe<String>(
        dedupeKey: 'world|wrld_alpha',
        lane: ApiRequestLane.worldDetails,
        request: (_) async {
          executions += 1;
          return completer.future;
        },
      );

      completer.complete('ok');

      expect(await first, 'ok');
      expect(await second, 'ok');
      final third = await runner.runWithReadDedupe<String>(
        dedupeKey: 'world|wrld_alpha',
        lane: ApiRequestLane.worldDetails,
        request: (_) async {
          executions += 1;
          return 'fresh';
        },
      );

      expect(third, 'fresh');
      expect(executions, 2);
      expect(recordedCalls, [
        ApiRequestLane.worldDetails,
        ApiRequestLane.worldDetails,
      ]);
    });

    test('throws a clear error when a dedupe key is reused for a different type', () {
      runner.runWithReadDedupe<String>(
        dedupeKey: 'world|wrld_alpha',
        lane: ApiRequestLane.worldDetails,
        request: (_) async => 'ok',
      );

      expect(
        () => runner.runWithReadDedupe<int>(
          dedupeKey: 'world|wrld_alpha',
          lane: ApiRequestLane.worldDetails,
          request: (_) async => 1,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('cannot reuse it for int'),
          ),
        ),
      );
    });

    test('runValidatedTransform records success for 2xx responses', () async {
      final result = await runner.runValidatedTransform<String, String>(
        lane: ApiRequestLane.authSession,
        request: (_) async => (
          ValidResponse(
            'ok',
            Response<String>(
              requestOptions: RequestOptions(path: '/auth/user'),
              statusCode: 200,
              data: 'ok',
            ),
          ),
          null,
        ),
      );

      expect(result.$1?.data, 'ok');
      expect(coordinator.remainingCooldown(ApiRequestLane.authSession), isNull);
      expect(recordedCalls, [ApiRequestLane.authSession]);
    });

    test('runValidatedTransform records cooldown from 429 invalid responses', () async {
      await runner.runValidatedTransform<String, String>(
        lane: ApiRequestLane.authSession,
        request: (_) async => (
          null,
          InvalidResponse(
            StateError('rate limited'),
            StackTrace.empty,
            response: Response<void>(
              requestOptions: RequestOptions(path: '/auth/user'),
              statusCode: 429,
              headers: Headers.fromMap(<String, List<String>>{
                'retry-after': ['12'],
              }),
            ),
          ),
        ),
      );

      final cooldown = coordinator.remainingCooldown(ApiRequestLane.authSession);
      expect(cooldown, isNotNull);
      expect(cooldown!.inSeconds, greaterThanOrEqualTo(11));
    });

    test('runValidatedTransform ignores responses without a status code', () async {
      final result = await runner.runValidatedTransform<String, String>(
        lane: ApiRequestLane.authSession,
        request: (_) async => (
          ValidResponse(
            'ok',
            Response<String>(
              requestOptions: RequestOptions(path: '/auth/user'),
              data: 'ok',
            ),
          ),
          null,
        ),
      );

      expect(result.$1?.data, 'ok');
      expect(coordinator.remainingCooldown(ApiRequestLane.authSession), isNull);
    });
  });
}
