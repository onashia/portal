import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../utils/app_logger.dart';
import '../utils/dio_error_logger.dart';

const Duration _selfInvite403LogDedupeWindow = Duration(minutes: 5);
const Duration _selfInvite403LogRetentionWindow = Duration(minutes: 15);
const int _httpForbidden = 403;
const int _httpBadRequest = 400;
const int _httpUnauthorized = 401;
const int _httpNotFound = 404;
const int _httpConflict = 409;
const int _httpRateLimited = 429;

enum InviteRetryOutcome {
  sent,
  cancelled,
  hardFailure,
  transientFailureExhausted,
  nonRetryableFailure,
}

@visibleForTesting
bool isSelfInviteForbiddenDioError(Object error) {
  if (error is! DioException) {
    return false;
  }
  return error.response?.statusCode == _httpForbidden;
}

@visibleForTesting
int? selfInviteStatusCode(Object error) {
  if (error is! DioException) {
    return null;
  }
  return error.response?.statusCode;
}

@visibleForTesting
bool isTransientSelfInviteError(Object error) {
  final statusCode = selfInviteStatusCode(error);
  if (statusCode != null) {
    if (statusCode == _httpNotFound ||
        statusCode == _httpConflict ||
        statusCode == _httpRateLimited ||
        statusCode >= 500) {
      return true;
    }
    return false;
  }

  if (error is DioException) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError;
  }

  return false;
}

@visibleForTesting
bool isHardStopSelfInviteError(Object error) {
  final statusCode = selfInviteStatusCode(error);
  if (statusCode == null) {
    return false;
  }
  return statusCode == _httpBadRequest ||
      statusCode == _httpUnauthorized ||
      statusCode == _httpForbidden;
}

@visibleForTesting
bool shouldLogSelfInvite403AsWarning({
  required DateTime now,
  required DateTime? previousLoggedAt,
  Duration dedupeWindow = _selfInvite403LogDedupeWindow,
}) {
  if (previousLoggedAt == null) {
    return true;
  }
  return now.difference(previousLoggedAt) >= dedupeWindow;
}

@visibleForTesting
String selfInviteDedupeKey({
  required String worldId,
  required String instanceId,
  required int statusCode,
}) {
  return '$worldId|$instanceId|$statusCode';
}

/// Sends in-game invites via the VRChat API.
class InviteService {
  final VrchatDart _api;
  final Map<String, DateTime> _selfInvite403LogAtByKey = <String, DateTime>{};
  final math.Random _random = math.Random();

  InviteService(this._api);

  void _pruneExpiredSelfInvite403LogKeys(DateTime now) {
    if (_selfInvite403LogAtByKey.isEmpty) {
      return;
    }

    _selfInvite403LogAtByKey.removeWhere(
      (_, loggedAt) =>
          now.difference(loggedAt) > _selfInvite403LogRetentionWindow,
    );
  }

  Future<void> inviteSelfToInstance(Instance instance) async {
    await inviteSelfToLocation(
      worldId: instance.worldId,
      instanceId: instance.instanceId,
    );
  }

  Future<void> inviteSelfToLocation({
    required String worldId,
    required String instanceId,
  }) async {
    try {
      await _sendSelfInvite(worldId: worldId, instanceId: instanceId);
      AppLogger.info(
        'Sent self-invite to $worldId:$instanceId',
        subCategory: 'invite',
      );
    } catch (e, s) {
      if (isSelfInviteForbiddenDioError(e)) {
        _log403Denial(worldId: worldId, instanceId: instanceId);
        return;
      }

      final logged = logDioException(
        'Failed to send self-invite',
        e,
        subCategory: 'invite',
        stackTrace: s,
        logResponseData: false,
      );
      if (!logged) {
        AppLogger.error(
          'Failed to send self-invite',
          subCategory: 'invite',
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  Future<InviteRetryOutcome> inviteSelfToLocationWithRetry({
    required String worldId,
    required String instanceId,
    Duration maxWindow = const Duration(seconds: 25),
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return InviteRetryOutcome.cancelled;
    }

    final start = DateTime.now();
    var attempt = 0;

    while (true) {
      if (cancelToken?.isCancelled == true) {
        return InviteRetryOutcome.cancelled;
      }

      attempt += 1;
      try {
        await _sendSelfInvite(
          worldId: worldId,
          instanceId: instanceId,
          cancelToken: cancelToken,
        );
        AppLogger.info(
          'Sent self-invite to $worldId:$instanceId after $attempt attempt(s)',
          subCategory: 'invite',
        );
        return InviteRetryOutcome.sent;
      } catch (e, s) {
        if (e is DioException && CancelToken.isCancel(e)) {
          return InviteRetryOutcome.cancelled;
        }

        if (isSelfInviteForbiddenDioError(e)) {
          _log403Denial(worldId: worldId, instanceId: instanceId);
          return InviteRetryOutcome.hardFailure;
        }

        if (isHardStopSelfInviteError(e)) {
          final statusCode = selfInviteStatusCode(e);
          AppLogger.warning(
            'Stopping self-invite retry on hard failure '
            '($statusCode) for $worldId:$instanceId',
            subCategory: 'invite',
          );
          return InviteRetryOutcome.hardFailure;
        }

        final isTransient = isTransientSelfInviteError(e);
        if (!isTransient) {
          final logged = logDioException(
            'Failed to send self-invite',
            e,
            subCategory: 'invite',
            stackTrace: s,
            logResponseData: false,
          );
          if (!logged) {
            AppLogger.error(
              'Failed to send self-invite',
              subCategory: 'invite',
              error: e,
              stackTrace: s,
            );
          }
          return InviteRetryOutcome.nonRetryableFailure;
        }

        final elapsed = DateTime.now().difference(start);
        final delay = _retryDelayForAttempt(attempt);
        if (elapsed + delay > maxWindow) {
          AppLogger.warning(
            'Stopping self-invite retry after transient failures for '
            '$worldId:$instanceId',
            subCategory: 'invite',
          );
          return InviteRetryOutcome.transientFailureExhausted;
        }

        AppLogger.debug(
          'Retrying self-invite attempt $attempt for $worldId:$instanceId '
          'after ${delay.inMilliseconds}ms',
          subCategory: 'invite',
        );
        if (cancelToken == null) {
          await Future<void>.delayed(delay);
        } else {
          await Future.any<void>([
            Future<void>.delayed(delay),
            cancelToken.whenCancel.then((_) {}),
          ]);
          if (cancelToken.isCancelled) {
            return InviteRetryOutcome.cancelled;
          }
        }
      }
    }
  }

  Duration _retryDelayForAttempt(int attempt) {
    const scheduleMs = <int>[700, 1200, 2000, 3000, 5000, 8000];
    final index = (attempt - 1).clamp(0, scheduleMs.length - 1);
    final jitterMs = _random.nextInt(251);
    return Duration(milliseconds: scheduleMs[index] + jitterMs);
  }

  Future<void> _sendSelfInvite({
    required String worldId,
    required String instanceId,
    CancelToken? cancelToken,
  }) async {
    await _api.rawApi.getInviteApi().inviteMyselfTo(
      worldId: worldId,
      instanceId: instanceId,
      cancelToken: cancelToken,
    );
  }

  void _log403Denial({required String worldId, required String instanceId}) {
    final now = DateTime.now();
    _pruneExpiredSelfInvite403LogKeys(now);

    final key = selfInviteDedupeKey(
      worldId: worldId,
      instanceId: instanceId,
      statusCode: _httpForbidden,
    );
    final shouldWarn = shouldLogSelfInvite403AsWarning(
      now: now,
      previousLoggedAt: _selfInvite403LogAtByKey[key],
    );
    _selfInvite403LogAtByKey[key] = now;

    final denialMessage = 'Self-invite denied (403) for $worldId:$instanceId';
    if (shouldWarn) {
      AppLogger.warning(denialMessage, subCategory: 'invite');
    } else {
      AppLogger.debug(
        '$denialMessage (repeated within 5 minutes)',
        subCategory: 'invite',
      );
    }
  }
}
