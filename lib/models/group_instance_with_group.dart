import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:flutter/foundation.dart';

@immutable
class GroupInstanceWithGroup {
  final Instance instance;
  final String groupId;

  const GroupInstanceWithGroup({required this.instance, required this.groupId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupInstanceWithGroup &&
          other.instance == instance &&
          other.groupId == groupId;

  @override
  int get hashCode => instance.hashCode ^ groupId.hashCode;

  @override
  String toString() =>
      'GroupInstanceWithGroup(groupId: $groupId, instance: $instance)';
}
