import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/services/invite_service.dart';

void main() {
  group('isSelfInviteForbiddenDioError', () {
    test('returns true for Dio 403 response', () {
      final request = RequestOptions(path: '/invite/myself/to');
      final error = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 403),
        type: DioExceptionType.badResponse,
      );

      expect(isSelfInviteForbiddenDioError(error), isTrue);
    });

    test('returns false for non-403 or non-Dio errors', () {
      final request = RequestOptions(path: '/invite/myself/to');
      final nonForbiddenError = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 500),
        type: DioExceptionType.badResponse,
      );

      expect(isSelfInviteForbiddenDioError(nonForbiddenError), isFalse);
      expect(isSelfInviteForbiddenDioError(StateError('nope')), isFalse);
    });
  });

  group('isTransientSelfInviteError', () {
    test('returns true for transient status codes', () {
      final request = RequestOptions(path: '/invite/myself/to');
      for (final statusCode in [404, 409, 429, 500, 502]) {
        final error = DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: statusCode),
          type: DioExceptionType.badResponse,
        );
        expect(isTransientSelfInviteError(error), isTrue);
      }
    });

    test('returns true for connection timeout and false for bad request', () {
      final request = RequestOptions(path: '/invite/myself/to');
      final timeoutError = DioException(
        requestOptions: request,
        type: DioExceptionType.connectionTimeout,
      );
      final badRequestError = DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 400),
        type: DioExceptionType.badResponse,
      );

      expect(isTransientSelfInviteError(timeoutError), isTrue);
      expect(isTransientSelfInviteError(badRequestError), isFalse);
    });
  });

  group('isHardStopSelfInviteError', () {
    test('returns true for hard stop status codes', () {
      final request = RequestOptions(path: '/invite/myself/to');
      for (final statusCode in [400, 401, 403]) {
        final error = DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: statusCode),
          type: DioExceptionType.badResponse,
        );
        expect(isHardStopSelfInviteError(error), isTrue);
      }
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
}
