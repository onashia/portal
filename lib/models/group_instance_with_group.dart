import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:flutter/foundation.dart';

@immutable
class GroupInstanceWithGroup {
  final Instance instance;
  final String groupId;
  final DateTime? firstDetectedAt;

  const GroupInstanceWithGroup({
    required this.instance,
    required this.groupId,
    this.firstDetectedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupInstanceWithGroup &&
          other.instance == instance &&
          other.groupId == groupId &&
          other.firstDetectedAt == firstDetectedAt;

  @override
  int get hashCode =>
      instance.hashCode ^ groupId.hashCode ^ (firstDetectedAt?.hashCode ?? 0);

  @override
  String toString() =>
      'GroupInstanceWithGroup(groupId: $groupId, instance: $instance, firstDetectedAt: $firstDetectedAt)';
}
