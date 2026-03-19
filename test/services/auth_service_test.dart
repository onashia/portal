import 'dart:convert';

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

dio.DioException _authFailure({
  required int statusCode,
  required Object? data,
}) {
  return dio.DioException(
    requestOptions: dio.RequestOptions(path: '/auth/user'),
    response: dio.Response<dynamic>(
      requestOptions: dio.RequestOptions(path: '/auth/user'),
      statusCode: statusCode,
      data: data,
    ),
    type: dio.DioExceptionType.badResponse,
  );
}

void main() {
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

  group('AuthService.login', () {
    test('logs a single-line failure summary when login is rejected', () async {
      when(
        () => mockAuthenticationApi.getCurrentUser(
          headers: any(named: 'headers'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) => Future<dio.Response<CurrentUser>>.error(
          _authFailure(
            statusCode: 403,
            data: <String, dynamic>{
              'error': <String, dynamic>{
                'message':
                    'Account banned\nfull backend payload should not be logged',
                'status_code': 403,
              },
            },
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
      'returns requires2FA when login response requests a known two-factor auth type',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <String>['totp'],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.requires2FA);
        expect(result.currentUser, isNull);
        expect(result.selectedTwoFactorMethod, TwoFactorAuthType.totp);
        expect(recordedLanes, contains(ApiRequestLane.authSession));
      },
    );

    test(
      'returns requires2FA when login response requests an email two-factor auth type',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <String>['emailOtp'],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.requires2FA);
        expect(result.selectedTwoFactorMethod, TwoFactorAuthType.emailOtp);
      },
    );

    test(
      'tolerates duplicate email 2FA entries in the login response',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <String>['emailOtp', 'emailOtp'],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.requires2FA);
        expect(result.selectedTwoFactorMethod, TwoFactorAuthType.emailOtp);
      },
    );

    test('ignores unknown 2FA types when a supported one is present', () async {
      when(
        () => mockAuthenticationApi.getCurrentUser(
          headers: any(named: 'headers'),
          extra: any(named: 'extra'),
        ),
      ).thenAnswer(
        (_) => Future<dio.Response<CurrentUser>>.error(
          _authFailure(
            statusCode: 200,
            data: <String, dynamic>{
              'requiresTwoFactorAuth': <String>['totp', 'future_method'],
            },
          ),
        ),
      );

      final result = await service.login('alice', 'secret');

      expect(result.status, AuthResultStatus.requires2FA);
      expect(result.selectedTwoFactorMethod, TwoFactorAuthType.totp);
      expect(loggedMessages.join('\n'), contains('unsupported 2FA types'));
      expect(loggedMessages.join('\n'), contains('future_method'));
    });

    test(
      'ignores non-string 2FA types when a supported one is present',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <Object>['totp', 42],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.requires2FA);
        expect(result.selectedTwoFactorMethod, TwoFactorAuthType.totp);
        expect(loggedMessages.join('\n'), contains('non-string 2FA types'));
        expect(loggedMessages.join('\n'), contains('42'));
      },
    );

    test(
      'returns explicit failure when only non-string 2FA types are returned',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <Object>[42, true],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.failure);
        expect(
          result.errorMessage,
          'Login failed: Unsupported VRChat 2FA challenge',
        );
        final logged = loggedMessages.join('\n');
        expect(logged, contains('non-string 2FA types'));
        expect(logged, contains('42'));
        expect(logged, contains('true'));
        expect(logged, contains('included no supported 2FA types'));
      },
    );

    test(
      'logs malformed and unsupported 2FA types while keeping supported ones',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <Object>['future_method', 42, 'totp'],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.requires2FA);
        expect(result.selectedTwoFactorMethod, TwoFactorAuthType.totp);
        final logged = loggedMessages.join('\n');
        expect(logged, contains('unsupported 2FA types'));
        expect(logged, contains('future_method'));
        expect(logged, contains('non-string 2FA types'));
        expect(logged, contains('42'));
      },
    );

    test(
      'returns explicit failure when only recovery-code auth is returned',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <String>['otp'],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.failure);
        final errorMessage = result.errorMessage;
        expect(errorMessage, isNotNull);
        expect(
          errorMessage,
          contains('Portal does not accept VRChat recovery codes'),
        );
        expect(errorMessage, contains('single-use emergency credential'));
        expect(
          errorMessage,
          contains('official VRChat website or VRChat client'),
        );
        final logged = loggedMessages.join('\n');
        expect(logged, contains('recovery-code 2FA'));
        expect(logged, contains('single-use emergency credentials'));
      },
    );

    test(
      'returns explicit failure when only unknown 2FA types are returned',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{
                'requiresTwoFactorAuth': <String>['future_method'],
              },
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.failure);
        expect(
          result.errorMessage,
          'Login failed: Unsupported VRChat 2FA challenge',
        );
      },
    );

    test(
      'returns failure when the API returns an empty 2FA type list',
      () async {
        when(
          () => mockAuthenticationApi.getCurrentUser(
            headers: any(named: 'headers'),
            extra: any(named: 'extra'),
          ),
        ).thenAnswer(
          (_) => Future<dio.Response<CurrentUser>>.error(
            _authFailure(
              statusCode: 200,
              data: <String, dynamic>{'requiresTwoFactorAuth': <String>[]},
            ),
          ),
        );

        final result = await service.login('alice', 'secret');

        expect(result.status, AuthResultStatus.failure);
        expect(
          result.errorMessage,
          'Login failed: Unsupported VRChat 2FA challenge',
        );
        expect(
          loggedMessages.join('\n'),
          contains('included no supported 2FA types'),
        );
      },
    );

    test('encodes special-character credentials per VRChat auth docs', () async {
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

      await service.login('alice+vr@example.com', 'pa ss:%+word');

      final headers =
          verify(
                () => mockAuthenticationApi.getCurrentUser(
                  headers: captureAny(named: 'headers'),
                  extra: any(named: 'extra'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      final expectedAuthorization =
          'Basic ${base64.encode(utf8.encode('${Uri.encodeComponent('alice+vr@example.com')}:'
          '${Uri.encodeComponent('pa ss:%+word')}'))}';
      expect(headers['Authorization'], expectedAuthorization);
    });
  });

  group('AuthService.logout', () {
    test('returns success when logout succeeds', () async {
      when(
        () => mockAuthenticationApi.logout(extra: any(named: 'extra')),
      ).thenAnswer(
        (_) async => dio.Response<Success>(
          requestOptions: dio.RequestOptions(path: '/auth/logout'),
          statusCode: 200,
          data: Success(),
        ),
      );

      final result = await service.logout();

      expect(result.status, AuthResultStatus.success);
      expect(recordedLanes, contains(ApiRequestLane.authSession));
      final extra =
          verify(
                () => mockAuthenticationApi.logout(
                  extra: captureAny(named: 'extra'),
                ),
              ).captured.single
              as Map<String, dynamic>?;
      expect(
        apiRequestLaneFromExtraValue(extra?[portalApiLaneExtraKey]),
        ApiRequestLane.authSession,
      );
    });

    test('returns failure when logout throws', () async {
      when(
        () => mockAuthenticationApi.logout(extra: any(named: 'extra')),
      ).thenThrow(StateError('logout exploded'));

      final result = await service.logout();

      expect(result.status, AuthResultStatus.failure);
      expect(result.errorMessage, 'Logout failed: Bad state: logout exploded');
    });
  });

  group('AuthService.checkExistingSession', () {
    test('returns success when an authenticated session exists', () async {
      final currentUser = _MockCurrentUser();
      when(
        () => mockAuthenticationApi.getCurrentUser(extra: any(named: 'extra')),
      ).thenAnswer(
        (_) async => dio.Response<CurrentUser>(
          requestOptions: dio.RequestOptions(path: '/auth/user'),
          statusCode: 200,
          data: currentUser,
        ),
      );

      final result = await service.checkExistingSession();

      expect(result.status, AuthResultStatus.success);
      expect(result.currentUser, same(currentUser));
      expect(recordedLanes, contains(ApiRequestLane.authSession));
    });

    test('returns failure when no valid existing session is found', () async {
      when(
        () => mockAuthenticationApi.getCurrentUser(extra: any(named: 'extra')),
      ).thenAnswer(
        (_) => Future<dio.Response<CurrentUser>>.error(
          _authFailure(
            statusCode: 401,
            data: <String, dynamic>{
              'error': <String, dynamic>{
                'message': 'Missing credentials',
                'status_code': 401,
              },
            },
          ),
        ),
      );

      final result = await service.checkExistingSession();

      expect(result.status, AuthResultStatus.failure);
      expect(result.currentUser, isNull);
      expect(result.errorMessage, isNull);
    });

    test(
      'returns failure with an error message when session check throws',
      () async {
        when(
          () =>
              mockAuthenticationApi.getCurrentUser(extra: any(named: 'extra')),
        ).thenThrow(StateError('session exploded'));

        final result = await service.checkExistingSession();

        expect(result.status, AuthResultStatus.failure);
        expect(
          result.errorMessage,
          'Session check failed: Bad state: session exploded',
        );
      },
    );
  });
}
