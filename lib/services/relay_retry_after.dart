import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import 'api_rate_limit_coordinator.dart';

Duration clampRelayRetryAfter(Duration retryAfter) {
  if (retryAfter <= Duration.zero) {
    return Duration.zero;
  }

  final maxRetryAfter = Duration(
    seconds: AppConstants.relayMaxRetryAfterSeconds,
  );
  if (retryAfter > maxRetryAfter) {
    return maxRetryAfter;
  }
  return retryAfter;
}

Duration? parseRelayRetryAfterFromPayload(Object? data) {
  if (data is! Map<String, dynamic>) {
    return null;
  }

  final retryAfterSeconds = (data['retryAfterSeconds'] as num?)?.toInt();
  if (retryAfterSeconds == null) {
    return null;
  }

  return clampRelayRetryAfter(Duration(seconds: retryAfterSeconds));
}

Duration? parseRelayRetryAfter({
  required Object? data,
  required Headers? headers,
  required DateTime Function() now,
}) {
  final payloadRetryAfter = parseRelayRetryAfterFromPayload(data);
  if (payloadRetryAfter != null) {
    return payloadRetryAfter;
  }

  final headerRetryAfter = parseRetryAfterHeaders(headers, now: now());
  if (headerRetryAfter == null) {
    return null;
  }

  return clampRelayRetryAfter(headerRetryAfter);
}
