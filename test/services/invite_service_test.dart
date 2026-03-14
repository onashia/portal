import 'package:dio/dio.dart' as dio;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/services/invite_service.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockVrchatRawApi extends Mock implements VrchatDartGenerated {}

class _MockInviteApi extends Mock implements InviteApi {}

class _FakeCancelToken extends Fake implements dio.CancelToken {}

class _FakeSentNotification extends Fake implements SentNotification {}

dio.DioException _inviteError({
  int? statusCode,
  dio.DioExceptionType type = dio.DioExceptionType.badResponse,
}) {
  final request = dio.RequestOptions(path: '/invite/myself/to');
  return dio.DioException(
    requestOptions: request,
    response: statusCode == null
        ? null
        : dio.Response(requestOptions: request, statusCode: statusCode),
    type: type,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeCancelToken());
  });

  group('isSelfInviteForbiddenDioError', () {
    test('returns true for Dio 403 response', () {
      final request = dio.RequestOptions(path: '/invite/myself/to');
      final error = dio.DioException(
        requestOptions: request,
        response: dio.Response(requestOptions: request, statusCode: 403),
        type: dio.DioExceptionType.badResponse,
      );

      expect(isSelfInviteForbiddenDioError(error), isTrue);
    });

    test('returns false for non-403 or non-Dio errors', () {
      final request = dio.RequestOptions(path: '/invite/myself/to');
      final nonForbiddenError = dio.DioException(
        requestOptions: request,
        response: dio.Response(requestOptions: request, statusCode: 500),
        type: dio.DioExceptionType.badResponse,
      );

      expect(isSelfInviteForbiddenDioError(nonForbiddenError), isFalse);
      expect(isSelfInviteForbiddenDioError(StateError('nope')), isFalse);
    });
  });

  group('isTransientSelfInviteError', () {
    test('returns true for transient status codes', () {
      final request = dio.RequestOptions(path: '/invite/myself/to');
      for (final statusCode in [404, 409, 429, 500, 502]) {
        final error = dio.DioException(
          requestOptions: request,
          response: dio.Response(
            requestOptions: request,
            statusCode: statusCode,
          ),
          type: dio.DioExceptionType.badResponse,
        );
        expect(isTransientSelfInviteError(error), isTrue);
      }
    });

    test('returns true for connection timeout and false for bad request', () {
      final request = dio.RequestOptions(path: '/invite/myself/to');
      final timeoutError = dio.DioException(
        requestOptions: request,
        type: dio.DioExceptionType.connectionTimeout,
      );
      final badRequestError = dio.DioException(
        requestOptions: request,
        response: dio.Response(requestOptions: request, statusCode: 400),
        type: dio.DioExceptionType.badResponse,
      );

      expect(isTransientSelfInviteError(timeoutError), isTrue);
      expect(isTransientSelfInviteError(badRequestError), isFalse);
    });
  });

  group('isHardStopSelfInviteError', () {
    test('returns true for hard stop status codes', () {
      final request = dio.RequestOptions(path: '/invite/myself/to');
      for (final statusCode in [400, 401, 403]) {
        final error = dio.DioException(
          requestOptions: request,
          response: dio.Response(
            requestOptions: request,
            statusCode: statusCode,
          ),
          type: dio.DioExceptionType.badResponse,
        );
        expect(isHardStopSelfInviteError(error), isTrue);
      }
    });
  });

  group('classifyInviteSendError', () {
    test('maps 403 errors to forbidden', () {
      final request = dio.RequestOptions(path: '/invite/myself/to');
      final error = dio.DioException(
        requestOptions: request,
        response: dio.Response(requestOptions: request, statusCode: 403),
        type: dio.DioExceptionType.badResponse,
      );

      expect(classifyInviteSendError(error), InviteSendOutcome.forbidden);
    });

    test('maps transient errors to transientFailure', () {
      final request = dio.RequestOptions(path: '/invite/myself/to');
      final error = dio.DioException(
        requestOptions: request,
        response: dio.Response(requestOptions: request, statusCode: 429),
        type: dio.DioExceptionType.badResponse,
      );

      expect(
        classifyInviteSendError(error),
        InviteSendOutcome.transientFailure,
      );
    });

    test('maps unexpected errors to nonRetryableFailure', () {
      expect(
        classifyInviteSendError(StateError('unexpected')),
        InviteSendOutcome.nonRetryableFailure,
      );
    });
  });

  group('shouldLogSelfInvite403AsWarning', () {
    test('logs warning when no previous entry exists', () {
      final now = DateTime.utc(2026, 2, 23, 12, 0, 0);

      expect(
        shouldLogSelfInvite403AsWarning(now: now, previousLoggedAt: null),
        isTrue,
      );
    });

    test('returns false for repeats inside 5-minute window', () {
      final previous = DateTime.utc(2026, 2, 23, 12, 0, 0);
      final now = previous.add(const Duration(minutes: 4, seconds: 59));

      expect(
        shouldLogSelfInvite403AsWarning(now: now, previousLoggedAt: previous),
        isFalse,
      );
    });

    test('returns true at or beyond 5-minute window', () {
      final previous = DateTime.utc(2026, 2, 23, 12, 0, 0);
      final atWindow = previous.add(const Duration(minutes: 5));
      final afterWindow = previous.add(const Duration(minutes: 6));

      expect(
        shouldLogSelfInvite403AsWarning(
          now: atWindow,
          previousLoggedAt: previous,
        ),
        isTrue,
      );
      expect(
        shouldLogSelfInvite403AsWarning(
          now: afterWindow,
          previousLoggedAt: previous,
        ),
        isTrue,
      );
    });
  });

  group('selfInviteDedupeKey', () {
    test('creates distinct keys for distinct instance targets', () {
      final keyA = selfInviteDedupeKey(
        worldId: 'wrld_alpha',
        instanceId: 'inst_a',
        statusCode: 403,
      );
      final keyB = selfInviteDedupeKey(
        worldId: 'wrld_alpha',
        instanceId: 'inst_b',
        statusCode: 403,
      );

      expect(keyA, isNot(equals(keyB)));
    });
  });

  group('InviteService public methods', () {
    late _MockVrchatDart mockApi;
    late _MockVrchatRawApi mockRawApi;
    late _MockInviteApi mockInviteApi;
    late InviteService service;

    setUp(() {
      mockApi = _MockVrchatDart();
      mockRawApi = _MockVrchatRawApi();
      mockInviteApi = _MockInviteApi();
      service = InviteService(mockApi);

      when(() => mockApi.rawApi).thenReturn(mockRawApi);
      when(() => mockRawApi.getInviteApi()).thenReturn(mockInviteApi);
    });

    test('inviteSelfToLocation returns forbidden on 403', () async {
      when(
        () => mockInviteApi.inviteMyselfTo(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          cancelToken: null,
        ),
      ).thenThrow(_inviteError(statusCode: 403));

      final outcome = await service.inviteSelfToLocation(
        worldId: 'wrld_alpha',
        instanceId: 'inst_a',
      );

      expect(outcome, InviteSendOutcome.forbidden);
    });

    test(
      'inviteSelfToLocation returns transientFailure on transient error',
      () async {
        when(
          () => mockInviteApi.inviteMyselfTo(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            cancelToken: null,
          ),
        ).thenThrow(_inviteError(statusCode: 429));

        final outcome = await service.inviteSelfToLocation(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
        );

        expect(outcome, InviteSendOutcome.transientFailure);
      },
    );

    test(
      'inviteSelfToLocation returns nonRetryableFailure on non-transient error',
      () async {
        when(
          () => mockInviteApi.inviteMyselfTo(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            cancelToken: null,
          ),
        ).thenThrow(_inviteError(statusCode: 418));

        final outcome = await service.inviteSelfToLocation(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
        );

        expect(outcome, InviteSendOutcome.nonRetryableFailure);
      },
    );

    test('inviteSelfToLocationWithRetry returns hardFailure on 403', () async {
      when(
        () => mockInviteApi.inviteMyselfTo(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          cancelToken: null,
        ),
      ).thenThrow(_inviteError(statusCode: 403));

      final outcome = await service.inviteSelfToLocationWithRetry(
        worldId: 'wrld_alpha',
        instanceId: 'inst_a',
      );

      expect(outcome, InviteRetryOutcome.hardFailure);
    });

    test(
      'inviteSelfToLocationWithRetry returns transientFailureExhausted on transient error',
      () async {
        when(
          () => mockInviteApi.inviteMyselfTo(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            cancelToken: null,
          ),
        ).thenThrow(_inviteError(statusCode: 429));

        final outcome = await service.inviteSelfToLocationWithRetry(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          maxWindow: Duration.zero,
        );

        expect(outcome, InviteRetryOutcome.transientFailureExhausted);
      },
    );

    test(
      'inviteSelfToLocationWithRetry returns nonRetryableFailure on non-transient error',
      () async {
        when(
          () => mockInviteApi.inviteMyselfTo(
            worldId: 'wrld_alpha',
            instanceId: 'inst_a',
            cancelToken: null,
          ),
        ).thenThrow(_inviteError(statusCode: 418));

        final outcome = await service.inviteSelfToLocationWithRetry(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
        );

        expect(outcome, InviteRetryOutcome.nonRetryableFailure);
      },
    );

    test('inviteSelfToLocationWithRetry returns sent on success', () async {
      when(
        () => mockInviteApi.inviteMyselfTo(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          cancelToken: null,
        ),
      ).thenAnswer(
        (_) async => dio.Response<SentNotification>(
          requestOptions: dio.RequestOptions(path: '/invite/myself/to'),
          data: _FakeSentNotification(),
          statusCode: 200,
        ),
      );

      final outcome = await service.inviteSelfToLocationWithRetry(
        worldId: 'wrld_alpha',
        instanceId: 'inst_a',
      );

      expect(outcome, InviteRetryOutcome.sent);
    });

    test(
      'inviteSelfToLocationWithRetry returns cancelled before making a request',
      () async {
        final cancelToken = dio.CancelToken()..cancel('user_cancelled');

        final outcome = await service.inviteSelfToLocationWithRetry(
          worldId: 'wrld_alpha',
          instanceId: 'inst_a',
          cancelToken: cancelToken,
        );

        expect(outcome, InviteRetryOutcome.cancelled);
        verifyNever(
          () => mockInviteApi.inviteMyselfTo(
            worldId: any(named: 'worldId'),
            instanceId: any(named: 'instanceId'),
            cancelToken: any(named: 'cancelToken'),
          ),
        );
      },
    );
  });
}
