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
    late PortalApiRequestRunner runner;
    late DateTime currentTime;

    setUp(() {
      currentTime = DateTime.utc(2026, 2, 14, 12, 0, 0);
      coordinator = ApiRateLimitCoordinator(nowProvider: () => currentTime);
      recordedCalls = <ApiRequestLane?>[];
      runner = PortalApiRequestRunner(
        coordinator: coordinator,
        recordApiCall: ({lane}) => recordedCalls.add(lane),
        recordThrottledSkip: ({lane}) {},
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

    test(
      'run preserves cooldown when overlapping same-lane success completes after 429',
      () async {
        final rateLimitedGate = Completer<void>();
        final successGate = Completer<void>();

        final rateLimitedFuture = runner.run<String>(
          lane: ApiRequestLane.groupBaseline,
          request: (_) async {
            await rateLimitedGate.future;
            throw DioException(
              requestOptions: RequestOptions(
                path: '/groups/grp_alpha/instances',
              ),
              response: Response<void>(
                requestOptions: RequestOptions(
                  path: '/groups/grp_alpha/instances',
                ),
                statusCode: 429,
                headers: Headers.fromMap(<String, List<String>>{
                  'retry-after': ['30'],
                }),
              ),
              type: DioExceptionType.badResponse,
            );
          },
        );
        final successFuture = runner.run<String>(
          lane: ApiRequestLane.groupBaseline,
          request: (_) async {
            await successGate.future;
            return 'ok';
          },
        );

        rateLimitedGate.complete();
        await expectLater(rateLimitedFuture, throwsA(isA<DioException>()));
        successGate.complete();
        expect(await successFuture, 'ok');

        final cooldown = coordinator.remainingCooldown(
          ApiRequestLane.groupBaseline,
        );
        expect(cooldown, isNotNull);
        expect(cooldown!.inSeconds, greaterThanOrEqualTo(29));
      },
    );

    test(
      'run preserves cooldown when overlapping same-lane 429 completes after success',
      () async {
        final successGate = Completer<void>();
        final rateLimitedGate = Completer<void>();

        final successFuture = runner.run<String>(
          lane: ApiRequestLane.groupBaseline,
          request: (_) async {
            await successGate.future;
            return 'ok';
          },
        );
        final rateLimitedFuture = runner.run<String>(
          lane: ApiRequestLane.groupBaseline,
          request: (_) async {
            await rateLimitedGate.future;
            throw DioException(
              requestOptions: RequestOptions(
                path: '/groups/grp_beta/instances',
              ),
              response: Response<void>(
                requestOptions: RequestOptions(
                  path: '/groups/grp_beta/instances',
                ),
                statusCode: 429,
                headers: Headers.fromMap(<String, List<String>>{
                  'retry-after': ['30'],
                }),
              ),
              type: DioExceptionType.badResponse,
            );
          },
        );

        successGate.complete();
        expect(await successFuture, 'ok');
        rateLimitedGate.complete();
        await expectLater(rateLimitedFuture, throwsA(isA<DioException>()));

        final cooldown = coordinator.remainingCooldown(
          ApiRequestLane.groupBaseline,
        );
        expect(cooldown, isNotNull);
        expect(cooldown!.inSeconds, greaterThanOrEqualTo(29));
      },
    );

    test(
      'dedupes concurrent read requests by key and cleans up in-flight state',
      () async {
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
      },
    );

    test(
      'throws a clear error when a dedupe key is reused for a different type',
      () {
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
      },
    );

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

    test(
      'runValidatedTransform records cooldown from 429 invalid responses',
      () async {
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

        final cooldown = coordinator.remainingCooldown(
          ApiRequestLane.authSession,
        );
        expect(cooldown, isNotNull);
        expect(cooldown!.inSeconds, greaterThanOrEqualTo(11));
      },
    );

    test(
      'runValidatedTransform records cooldown from thrown 429 Dio errors',
      () async {
        await expectLater(
          runner.runValidatedTransform<String, String>(
            lane: ApiRequestLane.authSession,
            request: (_) async {
              throw DioException(
                requestOptions: RequestOptions(path: '/auth/user'),
                response: Response<void>(
                  requestOptions: RequestOptions(path: '/auth/user'),
                  statusCode: 429,
                  headers: Headers.fromMap(<String, List<String>>{
                    'retry-after': ['9'],
                  }),
                ),
                type: DioExceptionType.badResponse,
              );
            },
          ),
          throwsA(isA<DioException>()),
        );

        final cooldown = coordinator.remainingCooldown(
          ApiRequestLane.authSession,
        );
        expect(cooldown, isNotNull);
        expect(cooldown!.inSeconds, greaterThanOrEqualTo(8));
      },
    );

    test(
      'runValidatedTransform does not create cooldown from non-429 Dio errors',
      () async {
        await expectLater(
          runner.runValidatedTransform<String, String>(
            lane: ApiRequestLane.authSession,
            request: (_) async {
              throw DioException(
                requestOptions: RequestOptions(path: '/auth/user'),
                response: Response<void>(
                  requestOptions: RequestOptions(path: '/auth/user'),
                  statusCode: 500,
                ),
                type: DioExceptionType.badResponse,
              );
            },
          ),
          throwsA(isA<DioException>()),
        );

        expect(
          coordinator.remainingCooldown(ApiRequestLane.authSession),
          isNull,
        );
      },
    );

    test(
      'runValidatedTransform does not clear an active cooldown on non-429 validated responses',
      () async {
        coordinator.recordRateLimited(
          ApiRequestLane.authSession,
          retryAfter: const Duration(seconds: 30),
        );

        final result = await runner.runValidatedTransform<String, String>(
          lane: ApiRequestLane.authSession,
          request: (_) async => (
            null,
            InvalidResponse(
              StateError('unauthorized'),
              StackTrace.empty,
              response: Response<void>(
                requestOptions: RequestOptions(path: '/auth/user'),
                statusCode: 401,
              ),
            ),
          ),
        );

        expect(result.$1, isNull);
        expect(result.$2, isNotNull);
        expect(
          coordinator.remainingCooldown(ApiRequestLane.authSession),
          isNotNull,
        );
      },
    );

    test(
      'runValidatedTransform clears cooldown after it has already expired',
      () async {
        coordinator.recordRateLimited(
          ApiRequestLane.authSession,
          retryAfter: const Duration(seconds: 30),
        );
        currentTime = currentTime.add(const Duration(seconds: 31));

        final result = await runner.runValidatedTransform<String, String>(
          lane: ApiRequestLane.authSession,
          request: (_) async => (
            null,
            InvalidResponse(
              StateError('unauthorized'),
              StackTrace.empty,
              response: Response<void>(
                requestOptions: RequestOptions(path: '/auth/user'),
                statusCode: 401,
              ),
            ),
          ),
        );

        expect(result.$1, isNull);
        expect(result.$2, isNotNull);
        expect(
          coordinator.remainingCooldown(ApiRequestLane.authSession),
          isNull,
        );
      },
    );

    test(
      'runValidatedTransform ignores responses without a status code',
      () async {
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
        expect(
          coordinator.remainingCooldown(ApiRequestLane.authSession),
          isNull,
        );
      },
    );
  });
}
