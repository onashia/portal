import 'package:vrchat_dart/vrchat_dart.dart';
import 'group_monitor_storage.dart';

bool shouldAttemptSelfInviteForInstance(Instance instance) {
  return hasValidSelfInviteIdentifiers(instance);
}

bool hasValidSelfInviteIdentifiers(Instance instance) {
  if (instance.worldId.isEmpty || instance.instanceId.isEmpty) {
    return false;
  }

  return true;
}

bool shouldDeprioritizeSelfInviteForCapacity(Instance instance) {
  return instance.hasCapacityForYou == false;
}

({
  String? boostedGroupId,
  DateTime? boostExpiresAt,
  bool shouldClear,
  bool logExpired,
})
resolveLoadedBoostSettings({
  required GroupMonitorBoostSettings settings,
  required DateTime now,
}) {
  final boostedGroupId = settings.groupId;
  final boostExpiresAt = settings.expiresAt;

  if (boostedGroupId != null && boostExpiresAt != null) {
    if (boostExpiresAt.isAfter(now)) {
      return (
        boostedGroupId: boostedGroupId,
        boostExpiresAt: boostExpiresAt,
        shouldClear: false,
        logExpired: false,
      );
    }

    return (
      boostedGroupId: null,
      boostExpiresAt: null,
      shouldClear: true,
      logExpired: true,
    );
  }

  if (boostedGroupId != null || boostExpiresAt != null) {
    return (
      boostedGroupId: null,
      boostExpiresAt: null,
      shouldClear: true,
      logExpired: false,
    );
  }

  return (
    boostedGroupId: null,
    boostExpiresAt: null,
    shouldClear: false,
    logExpired: false,
  );
}
