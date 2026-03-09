import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import 'invite_service.dart';
import '../models/group_instance_with_group.dart';
import '../models/relay_hint_message.dart';

/// Encapsulates the result of an auto-invite operation.
class AutoInviteResult {
  /// The target instance the user was invited to.
  final GroupInstanceWithGroup target;

  /// The time in milliseconds the invite operation took.
  final int latencyMs;

  const AutoInviteResult({required this.target, required this.latencyMs});
}

/// Service for automatically inviting users to group instances.
///
/// Handles selection of the most populated instance and tracks invite latency.
/// This is used when a group becomes active during monitoring to automatically
/// join the best available instance.
class AutoInviteService {
  AutoInviteService(this.inviteService);

  final InviteService inviteService;

  /// Attempts to automatically invite to an already resolved target.
  ///
  /// Only invites if [enabled] and [hasBaseline] are true.
  Future<AutoInviteResult?> attemptAutoInviteTarget({
    required GroupInstanceWithGroup target,
    required bool enabled,
    required bool hasBaseline,
  }) async {
    if (!enabled || !hasBaseline) {
      return null;
    }

    AppLogger.info(
      'Attempting auto-invite for group ${target.groupId} '
      '(${target.instance.worldId}:${target.instance.instanceId}, '
      'users=${target.instance.nUsers})',
      subCategory: 'group_monitor',
    );

    final start = DateTime.now();
    await inviteService.inviteSelfToInstance(target.instance);
    final latencyMs = DateTime.now().difference(start).inMilliseconds;

    AppLogger.info(
      'Auto-invite completed for group ${target.groupId} '
      '(${target.instance.worldId}:${target.instance.instanceId}, '
      'latency=${latencyMs}ms)',
      subCategory: 'group_monitor',
    );

    return AutoInviteResult(target: target, latencyMs: latencyMs);
  }

  /// Attempts to auto-invite from a relay hint even when local instance polling
  /// has not observed the instance yet.
  Future<InviteRetryOutcome?> attemptAutoInviteFromHint({
    required RelayHintMessage hint,
    required bool enabled,
    Duration maxRetryWindow = const Duration(seconds: 25),
    CancelToken? cancelToken,
  }) async {
    if (!enabled || !hint.isStructurallyValid || hint.isExpired()) {
      return null;
    }

    return inviteService.inviteSelfToLocationWithRetry(
      worldId: hint.worldId,
      instanceId: hint.instanceId,
      maxWindow: maxRetryWindow,
      cancelToken: cancelToken,
    );
  }
}
