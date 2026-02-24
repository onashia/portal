import '../models/group_instance_with_group.dart';

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
