import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/dio_error_logger.dart';

void main() {
  group('sanitizedAuthErrorDetails', () {
    test('includes only type and status code for DioException', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/login'),
        response: Response(
          statusCode: 401,
          data: {'message': 'bad credentials'},
          requestOptions: RequestOptions(path: '/login'),
        ),
        type: DioExceptionType.badResponse,
      );

      expect(sanitizedAuthErrorDetails(error), {
        'type': DioExceptionType.badResponse.toString(),
        'statusCode': 401,
      });
    });

    test('does not include URI, message, or response data', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/login'),
        response: Response(
          statusCode: 429,
          data: {'detail': 'too many requests'},
          requestOptions: RequestOptions(path: '/login'),
        ),
        type: DioExceptionType.badResponse,
        message: 'raw backend detail',
      );

      final details = sanitizedAuthErrorDetails(error);
      expect(details.containsKey('uri'), isFalse);
      expect(details.containsKey('message'), isFalse);
      expect(details.containsKey('data'), isFalse);
    });

    test('falls back to runtime type for non-Dio errors', () {
      expect(sanitizedAuthErrorDetails(StateError('boom')), {
        'type': 'StateError',
      });
    });
  });

  group('logAuthException', () {
    late List<String> loggedMessages;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      loggedMessages = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          loggedMessages.add(message);
        }
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('includes stack traces while keeping auth payload sanitized', () {
      final requestOptions = RequestOptions(
        path: '/login',
        baseUrl: 'https://api.vrchat.cloud/api/1',
      );
      final error = DioException(
        requestOptions: requestOptions,
        response: Response(
          statusCode: 401,
          data: {'detail': 'bad credentials'},
          requestOptions: requestOptions,
        ),
        type: DioExceptionType.badResponse,
        message: 'raw backend detail',
      );
      final stackTrace = StackTrace.fromString('test stack trace');

      logAuthException('Login', error, stackTrace);

      final logged = loggedMessages.join('\n');
      expect(logged, contains('Login failed'));
      expect(logged, contains('statusCode: 401'));
      expect(logged, contains('stack=test stack trace'));
      expect(logged, isNot(contains('raw backend detail')));
      expect(logged, isNot(contains('/login')));
      expect(logged, isNot(contains('bad credentials')));
    });
  });
}
