import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:portal/services/portal_api_request_runner.dart';
import 'package:portal/services/two_factor_auth_service.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockVrchatRawApi extends Mock implements VrchatDartGenerated {}

class _MockAuthenticationApi extends Mock implements AuthenticationApi {}

class _MockCurrentUser extends Mock implements CurrentUser {}

class _FakeTwoFactorAuthCode extends Fake implements TwoFactorAuthCode {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTwoFactorAuthCode());
  });

  group('TwoFactorAuthService.verify2FA', () {
    late _MockVrchatDart mockApi;
    late _MockVrchatRawApi mockRawApi;
    late _MockAuthenticationApi mockAuthenticationApi;
    late TwoFactorAuthService service;
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
      service = TwoFactorAuthService(mockApi, runner: runner);
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

    test('logs a single-line failure summary when 2FA is rejected', () async {
      when(
        () => mockAuthenticationApi.verify2FA(
          twoFactorAuthCode: any(named: 'twoFactorAuthCode'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) => Future<dio.Response<Verify2FAResult>>.error(
          dio.DioException(
            requestOptions: dio.RequestOptions(
              path: '/auth/twofactorauth/totp/verify',
            ),
            response: dio.Response<Map<String, dynamic>>(
              requestOptions: dio.RequestOptions(
                path: '/auth/twofactorauth/totp/verify',
              ),
              statusCode: 401,
              data: <String, dynamic>{
                'error': <String, dynamic>{
                  'message':
                      'Invalid 2FA code\nraw backend detail should not be logged',
                  'status_code': 401,
                },
              },
            ),
            type: dio.DioExceptionType.badResponse,
          ),
        ),
      );

      final result = await service.verify2FA('123456');

      expect(result.status, TwoFactorAuthResultStatus.failure);
      expect(recordedLanes, contains(ApiRequestLane.authTwoFactor));
      final invocation =
          verify(
                () => mockAuthenticationApi.verify2FA(
                  twoFactorAuthCode: any(named: 'twoFactorAuthCode'),
                  extra: captureAny(named: 'extra'),
                ),
              ).captured.single
              as Map<String, dynamic>?;
      expect(
        apiRequestLaneFromExtraValue(invocation?[portalApiLaneExtraKey]),
        ApiRequestLane.authTwoFactor,
      );

      final logged = loggedMessages.join('\n');
      expect(
        logged,
        contains('2FA verification rejected by API: 401: Invalid 2FA code'),
      );
      expect(
        logged,
        isNot(contains('raw backend detail should not be logged')),
      );
    });

    test('fetches current user after a successful 2FA verification', () async {
      final currentUser = _MockCurrentUser();
      when(
        () => mockAuthenticationApi.verify2FA(
          twoFactorAuthCode: any(named: 'twoFactorAuthCode'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) async => dio.Response<Verify2FAResult>(
          requestOptions: dio.RequestOptions(
            path: '/auth/twofactorauth/totp/verify',
          ),
          statusCode: 200,
          data: Verify2FAResult(verified: true),
        ),
      );
      when(
        () => mockAuthenticationApi.getCurrentUser(extra: any(named: 'extra')),
      ).thenAnswer(
        (_) async => dio.Response<CurrentUser>(
          requestOptions: dio.RequestOptions(path: '/auth/user'),
          statusCode: 200,
          data: currentUser,
        ),
      );

      final result = await service.verify2FA('123456');

      expect(result.status, TwoFactorAuthResultStatus.success);
      expect(result.currentUser, same(currentUser));
      expect(
        recordedLanes,
        containsAll(<ApiRequestLane>[
          ApiRequestLane.authTwoFactor,
          ApiRequestLane.authSession,
        ]),
      );
    });
  });
}
