import 'package:dio/dio.dart';
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
}
