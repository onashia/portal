import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/http_status_codes.dart';
import 'api_rate_limit_coordinator.dart';
import '../utils/app_logger.dart';
import '../utils/dio_error_logger.dart';
import 'portal_api_request_runner.dart';

const Duration _selfInvite403LogDedupeWindow = Duration(minutes: 5);
const Duration _selfInvite403LogRetentionWindow = Duration(minutes: 15);

enum InviteRetryOutcome {
  sent,
  cancelled,
  hardFailure,
  transientFailureExhausted,
  nonRetryableFailure,
}

enum InviteSendOutcome {
  sent,
  forbidden,
  transientFailure,
  nonRetryableFailure,
}

enum _InviteAttemptOutcome {
  sent,
  cancelled,
  forbidden,
  hardStop,
  transientFailure,
  nonRetryableFailure,
}

typedef _InviteAttemptResult = ({
  _InviteAttemptOutcome outcome,
  int? statusCode,
});

@visibleForTesting
bool isSelfInviteForbiddenDioError(Object error) {
  if (error is! DioException) {
    return false;
  }
  return error.response?.statusCode == AppHttpStatus.forbidden;
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
    if (statusCode == AppHttpStatus.notFound ||
        statusCode == AppHttpStatus.conflict ||
        statusCode == AppHttpStatus.tooManyRequests ||
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
InviteSendOutcome classifyInviteSendError(Object error) {
  if (isSelfInviteForbiddenDioError(error)) {
    return InviteSendOutcome.forbidden;
  }
  if (isTransientSelfInviteError(error)) {
    return InviteSendOutcome.transientFailure;
  }
  return InviteSendOutcome.nonRetryableFailure;
}

@visibleForTesting
bool isHardStopSelfInviteError(Object error) {
  final statusCode = selfInviteStatusCode(error);
  if (statusCode == null) {
    return false;
  }
  return statusCode == AppHttpStatus.badRequest ||
      statusCode == AppHttpStatus.unauthorized ||
      statusCode == AppHttpStatus.forbidden;
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
  final PortalApiRequestRunner _runner;
  final Map<String, DateTime> _selfInvite403LogAtByKey = <String, DateTime>{};
  final math.Random _random = math.Random();

  InviteService(this._api, {PortalApiRequestRunner? runner})
    : _runner = runner ?? PortalApiRequestRunner.untracked();

  void _pruneExpiredSelfInvite403LogKeys(DateTime now) {
    if (_selfInvite403LogAtByKey.isEmpty) {
      return;
    }

    _selfInvite403LogAtByKey.removeWhere(
      (_, loggedAt) =>
          now.difference(loggedAt) > _selfInvite403LogRetentionWindow,
    );
  }

  Future<InviteSendOutcome> inviteSelfToInstance(Instance instance) async {
    return inviteSelfToLocation(
      worldId: instance.worldId,
      instanceId: instance.instanceId,
    );
  }

  Future<InviteSendOutcome> inviteSelfToLocation({
    required String worldId,
    required String instanceId,
  }) async {
    final result = await _attemptSelfInvite(
      worldId: worldId,
      instanceId: instanceId,
      logNonForbiddenFailures: true,
    );
    return switch (result.outcome) {
      _InviteAttemptOutcome.sent => InviteSendOutcome.sent,
      _InviteAttemptOutcome.forbidden => InviteSendOutcome.forbidden,
      _InviteAttemptOutcome.transientFailure =>
        InviteSendOutcome.transientFailure,
      _InviteAttemptOutcome.hardStop ||
      _InviteAttemptOutcome.nonRetryableFailure ||
      _InviteAttemptOutcome.cancelled => InviteSendOutcome.nonRetryableFailure,
    };
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
      final result = await _attemptSelfInvite(
        worldId: worldId,
        instanceId: instanceId,
        cancelToken: cancelToken,
        successAttempt: attempt,
      );
      switch (result.outcome) {
        case _InviteAttemptOutcome.sent:
          return InviteRetryOutcome.sent;
        case _InviteAttemptOutcome.cancelled:
          return InviteRetryOutcome.cancelled;
        case _InviteAttemptOutcome.forbidden:
          return InviteRetryOutcome.hardFailure;
        case _InviteAttemptOutcome.hardStop:
          AppLogger.warning(
            'Stopping self-invite retry on hard failure '
            '(${result.statusCode}) for $worldId:$instanceId',
            subCategory: 'invite',
          );
          return InviteRetryOutcome.hardFailure;
        case _InviteAttemptOutcome.nonRetryableFailure:
          return InviteRetryOutcome.nonRetryableFailure;
        case _InviteAttemptOutcome.transientFailure:
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

  /// Returns the delay before the next retry attempt.
  ///
  /// Uses a near-Fibonacci schedule (700 → 1200 → 2000 → 3000 → 5000 → 8000 ms)
  /// with up to 250 ms of random jitter. The last bucket is repeated for any
  /// attempt beyond the sixth.
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
    await _runner.run(
      lane: ApiRequestLane.invite,
      request: (extra) => _api.rawApi.getInviteApi().inviteMyselfTo(
        worldId: worldId,
        instanceId: instanceId,
        cancelToken: cancelToken,
        extra: extra,
      ),
    );
  }

  Future<_InviteAttemptResult> _attemptSelfInvite({
    required String worldId,
    required String instanceId,
    CancelToken? cancelToken,
    bool logNonForbiddenFailures = false,
    int? successAttempt,
  }) async {
    try {
      await _sendSelfInvite(
        worldId: worldId,
        instanceId: instanceId,
        cancelToken: cancelToken,
      );
      final successMessage = successAttempt == null
          ? 'Sent self-invite to $worldId:$instanceId'
          : 'Sent self-invite to $worldId:$instanceId '
                'after $successAttempt attempt(s)';
      AppLogger.info(successMessage, subCategory: 'invite');
      return (outcome: _InviteAttemptOutcome.sent, statusCode: null);
    } catch (e, s) {
      if (e is DioException && CancelToken.isCancel(e)) {
        return (outcome: _InviteAttemptOutcome.cancelled, statusCode: null);
      }

      if (isSelfInviteForbiddenDioError(e)) {
        _log403Denial(worldId: worldId, instanceId: instanceId);
        return (
          outcome: _InviteAttemptOutcome.forbidden,
          statusCode: AppHttpStatus.forbidden,
        );
      }

      final statusCode = selfInviteStatusCode(e);
      final isHardStop = isHardStopSelfInviteError(e);
      final sendOutcome = classifyInviteSendError(e);
      final shouldLogFailure =
          logNonForbiddenFailures ||
          (sendOutcome == InviteSendOutcome.nonRetryableFailure && !isHardStop);
      if (shouldLogFailure) {
        _logNonForbiddenInviteFailure(error: e, stackTrace: s);
      }

      return (
        outcome: switch (sendOutcome) {
          InviteSendOutcome.sent => _InviteAttemptOutcome.sent,
          InviteSendOutcome.forbidden => _InviteAttemptOutcome.forbidden,
          InviteSendOutcome.transientFailure =>
            _InviteAttemptOutcome.transientFailure,
          InviteSendOutcome.nonRetryableFailure =>
            isHardStop
                ? _InviteAttemptOutcome.hardStop
                : _InviteAttemptOutcome.nonRetryableFailure,
        },
        statusCode: statusCode,
      );
    }
  }

  void _logNonForbiddenInviteFailure({
    required Object error,
    required StackTrace stackTrace,
  }) {
    final logged = logDioException(
      'Failed to send self-invite',
      error,
      subCategory: 'invite',
      stackTrace: stackTrace,
      logResponseData: false,
    );
    if (!logged) {
      AppLogger.error(
        'Failed to send self-invite',
        subCategory: 'invite',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _log403Denial({required String worldId, required String instanceId}) {
    final now = DateTime.now();
    _pruneExpiredSelfInvite403LogKeys(now);

    final key = selfInviteDedupeKey(
      worldId: worldId,
      instanceId: instanceId,
      statusCode: AppHttpStatus.forbidden,
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
