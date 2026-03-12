import 'package:vrchat_dart/vrchat_dart.dart';
import '../models/group_instance_with_group.dart';

bool areGroupInstanceStateRelevantFieldsEquivalent(
  Instance previous,
  Instance next,
) {
  return previous.hasCapacityForYou == next.hasCapacityForYou &&
      previous.capacity == next.capacity &&
      previous.queueEnabled == next.queueEnabled &&
      previous.queueSize == next.queueSize &&
      previous.groupAccessType == next.groupAccessType;
}

bool areGroupInstanceEntriesEquivalent(
  GroupInstanceWithGroup previous,
  GroupInstanceWithGroup next,
) {
  return previous.instance.instanceId == next.instance.instanceId &&
      previous.instance.worldId == next.instance.worldId &&
      previous.instance.world.name == next.instance.world.name &&
      previous.instance.nUsers == next.instance.nUsers &&
      areGroupInstanceStateRelevantFieldsEquivalent(
        previous.instance,
        next.instance,
      ) &&
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

  // Guard against duplicates within the previous list itself — if the map is
  // shorter than the list, at least two entries shared an instanceId.
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

  // Return the previous list by identity when nothing changed so that
  // Riverpod's equality diffing can short-circuit without a deep comparison.
  return (
    effectiveInstances: didChange ? mergedInstances : previousInstances,
    newInstances: newInstances,
    didChange: didChange,
  );
}
