import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/group_monitor_provider.dart';
import 'group_instances/group_instances_empty_state.dart';
import 'group_instances/instance_timeline_item.dart';

class GroupInstanceTimeline extends ConsumerWidget {
  final String userId;
  final VoidCallback onRefresh;

  const GroupInstanceTimeline({
    super.key,
    required this.userId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(groupMonitorProvider(userId));
    final allInstances = monitorState.allInstancesSorted;

    if (allInstances.isEmpty) {
      return GroupInstancesEmptyState(state: monitorState);
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: allInstances.length,
      itemBuilder: (context, index) {
        final instanceWithGroup = allInstances[index];
        final group = monitorState.allGroups.firstWhere(
          (g) => g.groupId == instanceWithGroup.groupId,
          orElse: () => LimitedUserGroups(),
        );
        final isLast = index == allInstances.length - 1;
        final isNewest =
            instanceWithGroup.instance.instanceId ==
            monitorState.newestInstanceId;

        return InstanceTimelineItem(
          instanceWithGroup: instanceWithGroup,
          group: group,
          isFirst: index == 0,
          isLast: isLast,
          isNewest: isNewest,
        );
      },
    );
  }
}
