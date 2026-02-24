import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/app_constants.dart';
import '../models/group_instance_with_group.dart';
import '../utils/chunked_async.dart';
import 'group_monitor_storage.dart';

final DateTime _stableTimestampFallback = DateTime.fromMillisecondsSinceEpoch(
  0,
);

DateTime _normalizedDetectedAt(DateTime? dateTime) =>
    dateTime ?? _stableTimestampFallback;

int _compareInstancesByDetectedDesc(
  GroupInstanceWithGroup a,
  GroupInstanceWithGroup b,
) {
  final byTime = _normalizedDetectedAt(
    b.firstDetectedAt,
  ).compareTo(_normalizedDetectedAt(a.firstDetectedAt));
  if (byTime != 0) {
    return byTime;
  }

  final byGroup = a.groupId.compareTo(b.groupId);
  if (byGroup != 0) {
    return byGroup;
  }

  return a.instance.instanceId.compareTo(b.instance.instanceId);
}

GroupInstanceWithGroup? pickNewestInstance(
  GroupInstanceWithGroup? current,
  GroupInstanceWithGroup candidate,
) {
  if (current == null) {
    return candidate;
  }

  return _compareInstancesByDetectedDesc(candidate, current) < 0
      ? candidate
      : current;
}

bool shouldAttemptSelfInviteForInstance(Instance instance) {
  if (instance.worldId.isEmpty || instance.instanceId.isEmpty) {
    return false;
  }

  // Conservative metadata gate: only explicit denial blocks attempts.
  return instance.canRequestInvite != false;
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

({
  List<GroupInstanceWithGroup> mergedInstances,
  List<GroupInstanceWithGroup> newInstances,
})
mergeFetchedGroupInstances({
  required String groupId,
  required List<Instance> fetchedInstances,
  required List<GroupInstanceWithGroup> previousInstances,
  required DateTime detectedAt,
}) {
  final previousInstancesById = {
    for (final previous in previousInstances)
      previous.instance.instanceId: previous,
  };

  final mergedInstances = <GroupInstanceWithGroup>[];
  final newInstances = <GroupInstanceWithGroup>[];

  for (final fetched in fetchedInstances) {
    final previous = previousInstancesById[fetched.instanceId];
    final merged = GroupInstanceWithGroup(
      instance: fetched,
      groupId: groupId,
      firstDetectedAt: previous?.firstDetectedAt ?? detectedAt,
    );
    mergedInstances.add(merged);
    if (previous == null) {
      newInstances.add(merged);
    }
  }

  return (mergedInstances: mergedInstances, newInstances: newInstances);
}

({
  List<GroupInstanceWithGroup> effectiveInstances,
  List<GroupInstanceWithGroup> newInstances,
  bool didChange,
})
mergeFetchedGroupInstancesWithDiff({
  required String groupId,
  required List<Instance> fetchedInstances,
  required List<GroupInstanceWithGroup> previousInstances,
  required DateTime detectedAt,
}) {
  final previousByInstanceId = <String, GroupInstanceWithGroup>{
    for (final previous in previousInstances)
      previous.instance.instanceId: previous,
  };

  var didChange =
      fetchedInstances.length != previousInstances.length ||
      previousByInstanceId.length != previousInstances.length;
  final mergedInstances = <GroupInstanceWithGroup>[];
  final newInstances = <GroupInstanceWithGroup>[];
  final fetchedInstanceIds = <String>{};

  for (final fetched in fetchedInstances) {
    fetchedInstanceIds.add(fetched.instanceId);
    final previous = previousByInstanceId[fetched.instanceId];
    final merged = GroupInstanceWithGroup(
      instance: fetched,
      groupId: groupId,
      firstDetectedAt: previous?.firstDetectedAt ?? detectedAt,
    );
    mergedInstances.add(merged);

    if (previous == null) {
      newInstances.add(merged);
      didChange = true;
      continue;
    }

    if (!areGroupInstanceEntriesEquivalent(previous, merged)) {
      didChange = true;
    }
  }

  for (final previousId in previousByInstanceId.keys) {
    if (!fetchedInstanceIds.contains(previousId)) {
      didChange = true;
      break;
    }
  }

  return (
    effectiveInstances: didChange ? mergedInstances : previousInstances,
    newInstances: newInstances,
    didChange: didChange,
  );
}

bool areGroupInstanceEntriesEquivalent(
  GroupInstanceWithGroup previous,
  GroupInstanceWithGroup next,
) {
  return previous.instance.instanceId == next.instance.instanceId &&
      previous.instance.worldId == next.instance.worldId &&
      previous.instance.world.name == next.instance.world.name &&
      previous.instance.nUsers == next.instance.nUsers &&
      previous.firstDetectedAt == next.firstDetectedAt;
}

bool areGroupInstanceListsEquivalent(
  List<GroupInstanceWithGroup> previous,
  List<GroupInstanceWithGroup> next,
) {
  if (identical(previous, next)) {
    return true;
  }

  if (previous.length != next.length) {
    return false;
  }

  final previousByInstanceId = <String, GroupInstanceWithGroup>{
    for (final entry in previous) entry.instance.instanceId: entry,
  };

  if (previousByInstanceId.length != previous.length) {
    return false;
  }

  final seenInstanceIds = <String>{};
  for (final nextEntry in next) {
    final instanceId = nextEntry.instance.instanceId;
    if (!seenInstanceIds.add(instanceId)) {
      return false;
    }

    final previousEntry = previousByInstanceId[instanceId];
    if (previousEntry == null ||
        !areGroupInstanceEntriesEquivalent(previousEntry, nextEntry)) {
      return false;
    }
  }

  return true;
}

bool areGroupInstancesByGroupEquivalent(
  Map<String, List<GroupInstanceWithGroup>> previous,
  Map<String, List<GroupInstanceWithGroup>> next,
) {
  if (identical(previous, next)) {
    return true;
  }

  if (previous.length != next.length) {
    return false;
  }

  for (final entry in previous.entries) {
    final nextGroupInstances = next[entry.key];
    if (nextGroupInstances == null ||
        !areGroupInstanceListsEquivalent(entry.value, nextGroupInstances)) {
      return false;
    }
  }

  return true;
}

bool hasGroupInstanceKeyMismatch({
  required Set<String> selectedGroupIds,
  required Map<String, List<GroupInstanceWithGroup>> groupInstances,
}) {
  if (groupInstances.length != selectedGroupIds.length) {
    return true;
  }

  for (final groupId in groupInstances.keys) {
    if (!selectedGroupIds.contains(groupId)) {
      return true;
    }
  }

  return false;
}

Map<String, List<GroupInstanceWithGroup>> selectGroupInstancesForState({
  required bool didInstancesChange,
  required Map<String, List<GroupInstanceWithGroup>> previousGroupInstances,
  required Map<String, List<GroupInstanceWithGroup>> nextGroupInstances,
}) {
  return didInstancesChange ? nextGroupInstances : previousGroupInstances;
}

Future<List<({String groupId, T? response})>> fetchGroupInstancesChunked<T>({
  required List<String> orderedGroupIds,
  required Future<T?> Function(String groupId) fetchGroupInstances,
  int maxConcurrentRequests = AppConstants.groupInstancesMaxConcurrentRequests,
}) async {
  return runInChunks<String, ({String groupId, T? response})>(
    items: orderedGroupIds,
    maxConcurrent: maxConcurrentRequests,
    operation: (groupId) async {
      final response = await fetchGroupInstances(groupId);
      return (groupId: groupId, response: response);
    },
  );
}

List<GroupInstanceWithGroup> sortGroupInstances(
  Iterable<GroupInstanceWithGroup> instances,
) {
  final sorted = instances.toList(growable: false);
  sorted.sort(_compareInstancesByDetectedDesc);
  return sorted;
}

String? newestInstanceIdFromGroupInstances(
  Map<String, List<GroupInstanceWithGroup>> groupInstances,
) {
  GroupInstanceWithGroup? newest;

  for (final groupEntries in groupInstances.values) {
    for (final instance in groupEntries) {
      newest = pickNewestInstance(newest, instance);
    }
  }

  return newest?.instance.instanceId;
}
