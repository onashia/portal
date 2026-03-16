import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/auth_service.dart';
import 'package:portal/services/portal_api_request_runner.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockVrchatRawApi extends Mock implements VrchatDartGenerated {}

class _MockAuthenticationApi extends Mock implements AuthenticationApi {}

class _MockCurrentUser extends Mock implements CurrentUser {}

void main() {
  group('AuthService.login', () {
    late _MockVrchatDart mockApi;
    late _MockVrchatRawApi mockRawApi;
    late _MockAuthenticationApi mockAuthenticationApi;
    late AuthService service;
    late List<String> loggedMessages;
    late DebugPrintCallback originalDebugPrint;
    late List<ApiRequestLane?> recordedLanes;

    setUp(() {
      mockApi = _MockVrchatDart();
      mockRawApi = _MockVrchatRawApi();
      mockAuthenticationApi = _MockAuthenticationApi();
      recordedLanes = <ApiRequestLane?>[];
      final runner = PortalApiRequestRunner(
        coordinator: ApiRateLimitCoordinator(),
        recordApiCall: ({lane}) => recordedLanes.add(lane),
        recordThrottledSkip: ({lane}) {},
      );
      service = AuthService(mockApi, runner: runner);
      loggedMessages = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          loggedMessages.add(message);
        }
      };

      when(() => mockApi.rawApi).thenReturn(mockRawApi);
      when(
        () => mockRawApi.getAuthenticationApi(),
      ).thenReturn(mockAuthenticationApi);
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('logs a single-line failure summary when login is rejected', () async {
      when(
        () => mockAuthenticationApi.getCurrentUser(
          headers: any(named: 'headers'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) => Future<dio.Response<CurrentUser>>.error(
          dio.DioException(
            requestOptions: dio.RequestOptions(path: '/auth/user'),
            response: dio.Response<Map<String, dynamic>>(
              requestOptions: dio.RequestOptions(path: '/auth/user'),
              statusCode: 403,
              data: <String, dynamic>{
                'error': <String, dynamic>{
                  'message':
                      'Account banned\nfull backend payload should not be logged',
                  'status_code': 403,
                },
              },
            ),
            type: dio.DioExceptionType.badResponse,
          ),
        ),
      );

      final result = await service.login('alice', 'secret');

      expect(result.status, AuthResultStatus.failure);
      expect(recordedLanes, contains(ApiRequestLane.authSession));
      final invocation =
          verify(
                () => mockAuthenticationApi.getCurrentUser(
                  headers: any(named: 'headers'),
                  extra: captureAny(named: 'extra'),
                ),
              ).captured.single
              as Map<String, dynamic>?;
      expect(
        apiRequestLaneFromExtraValue(invocation?[portalApiLaneExtraKey]),
        ApiRequestLane.authSession,
      );

      final logged = loggedMessages.join('\n');
      expect(logged, contains('Login rejected by API: 403: Account banned'));
      expect(
        logged,
        isNot(contains('full backend payload should not be logged')),
      );
    });

    test('returns success when authentication succeeds', () async {
      final currentUser = _MockCurrentUser();
      when(
        () => mockAuthenticationApi.getCurrentUser(
          headers: any(named: 'headers'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) async => dio.Response<CurrentUser>(
          requestOptions: dio.RequestOptions(path: '/auth/user'),
          statusCode: 200,
          data: currentUser,
        ),
      );
      when(() => currentUser.twoFactorAuthEnabled).thenReturn(false);

      final result = await service.login('alice', 'secret');

      expect(result.status, AuthResultStatus.success);
      expect(result.currentUser, same(currentUser));
      expect(recordedLanes, contains(ApiRequestLane.authSession));
    });

    test(
      'returns requires2FA when login response requests two-factor auth',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            dio.DioException(
              requestOptions: dio.RequestOptions(path: '/auth/user'),
              response: dio.Response<Map<String, dynamic>>(
                requestOptions: dio.RequestOptions(path: '/auth/user'),
                statusCode: 200,
                data: <String, dynamic>{
                  'requiresTwoFactorAuth': <String>['totp'],
                },
              ),
              type: dio.DioExceptionType.badResponse,
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.requires2FA);
        expect(result.currentUser, isNull);
        expect(recordedLanes, contains(ApiRequestLane.authSession));
      },
    );
  });
}
