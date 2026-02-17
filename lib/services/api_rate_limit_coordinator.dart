import 'dart:io';

import 'package:dio/dio.dart';

enum ApiRequestLane {
  userGroups,
  groupBaseline,
  groupBoost,
  calendar,
  status,
  image,
}

const String portalApiLaneExtraKey = 'portal_lane';

Map<String, dynamic> apiRequestLaneExtra(ApiRequestLane lane) {
  return <String, dynamic>{portalApiLaneExtraKey: lane.name};
}

ApiRequestLane? apiRequestLaneFromExtraValue(Object? value) {
  if (value is ApiRequestLane) {
    return value;
  }

  if (value is String) {
    for (final lane in ApiRequestLane.values) {
      if (lane.name == value) {
        return lane;
      }
    }
  }

  return null;
}

class ApiRateLimitCoordinator {
  ApiRateLimitCoordinator({
    DateTime Function()? nowProvider,
    this.initialFallbackBackoff = const Duration(seconds: 20),
    this.maxFallbackBackoff = const Duration(seconds: 120),
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final DateTime Function() _nowProvider;
  final Duration initialFallbackBackoff;
  final Duration maxFallbackBackoff;

  final Map<ApiRequestLane, DateTime> _blockedUntilByLane =
      <ApiRequestLane, DateTime>{};
  final Map<ApiRequestLane, int> _consecutiveRateLimitHitsByLane =
      <ApiRequestLane, int>{};

  bool canRequest(ApiRequestLane lane, {DateTime? now}) {
    return remainingCooldown(lane, now: now) == null;
  }

  Duration? remainingCooldown(ApiRequestLane lane, {DateTime? now}) {
    final currentTime = now ?? _nowProvider();
    final blockedUntil = _blockedUntilByLane[lane];
    if (blockedUntil == null || !blockedUntil.isAfter(currentTime)) {
      _blockedUntilByLane.remove(lane);
      return null;
    }

    return blockedUntil.difference(currentTime);
  }

  void recordSuccess(ApiRequestLane lane, {DateTime? now}) {
    _consecutiveRateLimitHitsByLane.remove(lane);
    remainingCooldown(lane, now: now);
  }

  void recordRateLimited(
    ApiRequestLane lane, {
    Duration? retryAfter,
    DateTime? now,
  }) {
    final currentTime = now ?? _nowProvider();
    final currentStreak = _consecutiveRateLimitHitsByLane[lane] ?? 0;
    final fallbackDelay = _fallbackBackoffForStreak(currentStreak);
    final effectiveDelay = retryAfter ?? _clampDelay(fallbackDelay);
    final nextBlockedUntil = currentTime.add(effectiveDelay);
    final previousBlockedUntil = _blockedUntilByLane[lane];

    if (previousBlockedUntil == null ||
        nextBlockedUntil.isAfter(previousBlockedUntil)) {
      _blockedUntilByLane[lane] = nextBlockedUntil;
    }

    _consecutiveRateLimitHitsByLane[lane] = currentStreak + 1;
  }

  Duration? parseRetryAfter(Object? retryAfterHeaderValue, {DateTime? now}) {
    if (retryAfterHeaderValue == null) {
      return null;
    }

    final currentTime = now ?? _nowProvider();
    final raw = retryAfterHeaderValue.toString().trim();
    if (raw.isEmpty) {
      return null;
    }

    final asSeconds = int.tryParse(raw);
    if (asSeconds != null) {
      if (asSeconds <= 0) {
        return Duration.zero;
      }
      return Duration(seconds: asSeconds);
    }

    final asDate = DateTime.tryParse(raw);
    if (asDate != null) {
      final delta = asDate.toUtc().difference(currentTime.toUtc());
      if (delta.isNegative) {
        return Duration.zero;
      }
      return delta;
    }

    try {
      final httpDate = HttpDate.parse(raw);
      final delta = httpDate.toUtc().difference(currentTime.toUtc());
      if (delta.isNegative) {
        return Duration.zero;
      }
      return delta;
    } catch (_) {
      return null;
    }
  }

  Duration? parseRetryAfterFromHeaders(Headers? headers, {DateTime? now}) {
    final retryAfterValue = headers?.value('retry-after');
    return parseRetryAfter(retryAfterValue, now: now);
  }

  Duration _fallbackBackoffForStreak(int streak) {
    final multiplier = 1 << streak.clamp(0, 16);
    final baseSeconds = initialFallbackBackoff.inSeconds * multiplier;
    return Duration(seconds: baseSeconds);
  }

  Duration _clampDelay(Duration value) {
    if (value <= Duration.zero) {
      return Duration.zero;
    }
    if (value > maxFallbackBackoff) {
      return maxFallbackBackoff;
    }
    return value;
  }
}

class ApiRateLimitInterceptor extends Interceptor {
  ApiRateLimitInterceptor(this._coordinator);

  final ApiRateLimitCoordinator _coordinator;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final lane = _laneForOptions(response.requestOptions);
    if (lane != null) {
      _coordinator.recordSuccess(lane);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final lane = _laneForOptions(err.requestOptions);
    if (lane != null && err.response?.statusCode == 429) {
      final retryAfter = _coordinator.parseRetryAfterFromHeaders(
        err.response?.headers,
      );
      _coordinator.recordRateLimited(lane, retryAfter: retryAfter);
    }
    handler.next(err);
  }

  ApiRequestLane? _laneForOptions(RequestOptions options) {
    return apiRequestLaneFromExtraValue(options.extra[portalApiLaneExtraKey]);
  }
}

void ensureApiRateLimitInterceptor(
  Dio dio,
  ApiRateLimitCoordinator coordinator,
) {
  final alreadyPresent = dio.interceptors
      .whereType<ApiRateLimitInterceptor>()
      .isNotEmpty;
  if (alreadyPresent) {
    return;
  }

  dio.interceptors.add(ApiRateLimitInterceptor(coordinator));
}
