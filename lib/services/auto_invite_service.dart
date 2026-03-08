import 'package:dio/dio.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../utils/app_logger.dart';
import 'invite_service.dart';
import '../models/group_instance_with_group.dart';
import '../models/relay_hint_message.dart';
import '../providers/group_invite_and_boost.dart';

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

  /// Attempts to automatically invite to the best instance in a group.
  ///
  /// Only invites if [enabled] and [hasBaseline] are true. Selects the instance
  /// with the most users and tracks operation latency.
  ///
  /// Returns [AutoInviteResult] if invite was attempted, null if conditions
  /// not met or no valid instance found.
  Future<AutoInviteResult?> attemptAutoInvite({
    required List<Instance> instances,
    required String groupId,
    required bool enabled,
    required bool hasBaseline,
  }) async {
    if (!enabled || !hasBaseline || instances.isEmpty) {
      return null;
    }

    final target = _selectInviteTarget(instances, groupId);
    if (target == null) {
      return null;
    }

    AppLogger.info(
      'Attempting auto-invite for group $groupId '
      '(${target.instance.worldId}:${target.instance.instanceId}, '
      'users=${target.instance.nUsers})',
      subCategory: 'group_monitor',
    );

    final start = DateTime.now();
    await inviteService.inviteSelfToInstance(target.instance);
    final latencyMs = DateTime.now().difference(start).inMilliseconds;

    AppLogger.info(
      'Auto-invite completed for group $groupId '
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

  GroupInstanceWithGroup? _selectInviteTarget(
    List<Instance> instances,
    String groupId,
  ) {
    final sorted = instances.toList(growable: false)
      ..sort((a, b) {
        final aDeprioritized = shouldDeprioritizeSelfInviteForCapacity(a);
        final bDeprioritized = shouldDeprioritizeSelfInviteForCapacity(b);
        if (aDeprioritized != bDeprioritized) {
          return aDeprioritized ? 1 : -1;
        }
        return b.nUsers.compareTo(a.nUsers);
      });

    Instance? topCandidate;
    for (final instance in sorted) {
      topCandidate ??= instance;
      if (!shouldAttemptSelfInviteForInstance(instance)) {
        final hasInvalidIdentifiers =
            instance.worldId.isEmpty || instance.instanceId.isEmpty;
        final skipReason = hasInvalidIdentifiers
            ? 'invalid instance identifiers'
            : 'instance metadata denies invite requests';
        AppLogger.warning(
          'Skipping invite candidate: $skipReason for group $groupId '
          '(${instance.worldId}:${instance.instanceId}, users=${instance.nUsers})',
          subCategory: 'group_monitor',
        );
        continue;
      }

      if (shouldDeprioritizeSelfInviteForCapacity(instance)) {
        AppLogger.info(
          'Proceeding with low-capacity invite candidate for group $groupId '
          '(${instance.worldId}:${instance.instanceId}, users=${instance.nUsers})',
          subCategory: 'group_monitor',
        );
      } else if (instance.canRequestInvite == false) {
        AppLogger.info(
          'Proceeding with group invite candidate despite '
          'canRequestInvite=false for group $groupId '
          '(${instance.worldId}:${instance.instanceId}, users=${instance.nUsers})',
          subCategory: 'group_monitor',
        );
      }

      if (!identical(instance, topCandidate)) {
        final reason = shouldDeprioritizeSelfInviteForCapacity(topCandidate)
            ? 'after deprioritizing higher-priority full candidates'
            : 'after skipping higher-priority invalid candidates';
        AppLogger.info(
          'Selected lower-population invite candidate for group $groupId '
          '(${instance.worldId}:${instance.instanceId}, users=${instance.nUsers}) '
          '$reason',
          subCategory: 'group_monitor',
        );
      }

      return GroupInstanceWithGroup(instance: instance, groupId: groupId);
    }

    if (topCandidate == null) {
      return null;
    }

    if (!shouldAttemptSelfInviteForInstance(topCandidate)) {
      final hasInvalidIdentifiers =
          topCandidate.worldId.isEmpty || topCandidate.instanceId.isEmpty;
      final skipReason = hasInvalidIdentifiers
          ? 'invalid instance identifiers'
          : 'instance metadata denies invite requests';
      AppLogger.warning(
        'Skipping invite: $skipReason for group $groupId',
        subCategory: 'group_monitor',
      );
    }
    return null;
  }
}
