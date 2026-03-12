import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'app_logger.dart';

/// Logs Dio-specific errors in a consistent format.
///
/// Returns true when [error] is a DioException and was logged. Returns false
/// when the error is not Dio-related.
bool logDioException(
  String context,
  Object error, {
  required String subCategory,
  StackTrace? stackTrace,
  bool logResponseData = true,
}) {
  if (error is! DioException) {
    return false;
  }

  final response = error.response;
  AppLogger.error(
    '$context DioException',
    subCategory: subCategory,
    error: {
      'type': error.type.toString(),
      'message': error.message,
      'uri': error.requestOptions.uri.toString(),
      'statusCode': response?.statusCode,
    },
    stackTrace: stackTrace,
  );

  if (logResponseData && response?.data != null) {
    AppLogger.debug(
      '$context Dio response data: ${response?.data}',
      subCategory: subCategory,
    );
  }

  return true;
}

/// Builds a minimal error payload for auth failures without including raw
/// response bodies, request URIs, or stack traces.
@visibleForTesting
Map<String, Object?> sanitizedAuthErrorDetails(Object error) {
  if (error is DioException) {
    return <String, Object?>{
      'type': error.type.toString(),
      if (error.response?.statusCode != null)
        'statusCode': error.response?.statusCode,
    };
  }

  return <String, Object?>{'type': error.runtimeType.toString()};
}

/// Logs an auth operation exception using both Dio-specific and general error
/// logging in a consistent format.
void logAuthException(String operation, Object e, StackTrace s) {
  AppLogger.error(
    '$operation failed',
    subCategory: 'auth',
    error: sanitizedAuthErrorDetails(e),
    stackTrace: s,
  );
}
