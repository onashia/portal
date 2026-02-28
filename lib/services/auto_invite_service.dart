import 'package:vrchat_dart/vrchat_dart.dart';

import '../utils/app_logger.dart';
import 'invite_service.dart';
import '../models/group_instance_with_group.dart';
import '../providers/group_invite_and_boost.dart';

class AutoInviteResult {
  final GroupInstanceWithGroup target;
  final int latencyMs;

  const AutoInviteResult({required this.target, required this.latencyMs});
}

class AutoInviteService {
  AutoInviteService(this.inviteService);

  final InviteService inviteService;

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

    final start = DateTime.now();
    await inviteService.inviteSelfToInstance(target.instance);
    final latencyMs = DateTime.now().difference(start).inMilliseconds;

    return AutoInviteResult(target: target, latencyMs: latencyMs);
  }

  GroupInstanceWithGroup? _selectInviteTarget(
    List<Instance> instances,
    String groupId,
  ) {
    Instance? best;
    for (final instance in instances) {
      if (best == null || instance.nUsers > best.nUsers) {
        best = instance;
      }
    }

    if (best == null) {
      return null;
    }

    if (!shouldAttemptSelfInviteForInstance(best)) {
      final hasInvalidIdentifiers =
          best.worldId.isEmpty || best.instanceId.isEmpty;
      final skipReason = hasInvalidIdentifiers
          ? 'invalid instance identifiers'
          : 'instance metadata denies invite requests';
      AppLogger.warning(
        'Skipping invite: $skipReason for group $groupId',
        subCategory: 'group_monitor',
      );
      return null;
    }
    return GroupInstanceWithGroup(instance: best, groupId: groupId);
  }
}
