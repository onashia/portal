import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../utils/app_logger.dart';
import '../utils/dio_error_logger.dart';

const Duration _selfInvite403LogDedupeWindow = Duration(minutes: 5);
const Duration _selfInvite403LogRetentionWindow = Duration(minutes: 15);
const int _httpForbidden = 403;

@visibleForTesting
bool isSelfInviteForbiddenDioError(Object error) {
  if (error is! DioException) {
    return false;
  }
  return error.response?.statusCode == _httpForbidden;
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
    try {
      await _api.rawApi.getInviteApi().inviteMyselfTo(
        worldId: instance.worldId,
        instanceId: instance.instanceId,
      );
      AppLogger.info(
        'Sent self-invite to ${instance.worldId}:${instance.instanceId}',
        subCategory: 'invite',
      );
    } catch (e, s) {
      if (isSelfInviteForbiddenDioError(e)) {
        final now = DateTime.now();
        _pruneExpiredSelfInvite403LogKeys(now);

        final key = selfInviteDedupeKey(
          worldId: instance.worldId,
          instanceId: instance.instanceId,
          statusCode: _httpForbidden,
        );
        final shouldWarn = shouldLogSelfInvite403AsWarning(
          now: now,
          previousLoggedAt: _selfInvite403LogAtByKey[key],
        );
        _selfInvite403LogAtByKey[key] = now;

        final denialMessage =
            'Self-invite denied (403) for '
            '${instance.worldId}:${instance.instanceId}';
        if (shouldWarn) {
          AppLogger.warning(denialMessage, subCategory: 'invite');
        } else {
          AppLogger.debug(
            '$denialMessage (repeated within 5 minutes)',
            subCategory: 'invite',
          );
        }
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
}
