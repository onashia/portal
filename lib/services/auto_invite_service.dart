import 'package:dio/dio.dart';

import '../utils/app_logger.dart';
import 'invite_service.dart';
import '../models/group_instance_with_group.dart';
import '../models/relay_hint_message.dart';

/// Service for automatically inviting users to group instances.
///
/// Dispatches invites to an already resolved target and handles relay hints.
class AutoInviteService {
  AutoInviteService(this.inviteService);

  final InviteService inviteService;

  /// Attempts to automatically invite to an already resolved target.
  ///
  /// Only invites if [enabled] and [hasBaseline] are true.
  Future<void> attemptAutoInviteTarget({
    required GroupInstanceWithGroup target,
    required bool enabled,
    required bool hasBaseline,
  }) async {
    if (!enabled || !hasBaseline) {
      return;
    }

    AppLogger.info(
      'Attempting auto-invite for group ${target.groupId} '
      '(${target.instance.worldId}:${target.instance.instanceId}, '
      'users=${target.instance.nUsers})',
      subCategory: 'group_monitor',
    );

    final start = DateTime.now();
    final outcome = await inviteService.inviteSelfToInstance(target.instance);
    final latencyMs = DateTime.now().difference(start).inMilliseconds;

    switch (outcome) {
      case InviteSendOutcome.sent:
        AppLogger.info(
          'Auto-invite completed for group ${target.groupId} '
          '(${target.instance.worldId}:${target.instance.instanceId}, '
          'latency=${latencyMs}ms)',
          subCategory: 'group_monitor',
        );
        return;
      case InviteSendOutcome.forbidden:
        AppLogger.info(
          'Auto-invite forbidden for group ${target.groupId} '
          '(${target.instance.worldId}:${target.instance.instanceId}, '
          'latency=${latencyMs}ms, outcome=${outcome.name})',
          subCategory: 'group_monitor',
        );
        return;
      case InviteSendOutcome.transientFailure:
        AppLogger.info(
          'Auto-invite transient failure for group ${target.groupId} '
          '(${target.instance.worldId}:${target.instance.instanceId}, '
          'latency=${latencyMs}ms, outcome=${outcome.name})',
          subCategory: 'group_monitor',
        );
        return;
      case InviteSendOutcome.nonRetryableFailure:
        AppLogger.info(
          'Auto-invite non-retryable failure for group ${target.groupId} '
          '(${target.instance.worldId}:${target.instance.instanceId}, '
          'latency=${latencyMs}ms, outcome=${outcome.name})',
          subCategory: 'group_monitor',
        );
        return;
    }
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
