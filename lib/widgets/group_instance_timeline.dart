import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/group_monitor_provider.dart';
import 'animated_fade_slide.dart';
import 'common/loading_state.dart';
import 'group_instances/group_instances_empty_state.dart';
import 'group_instances/instance_timeline_item.dart';

class GroupInstanceTimeline extends ConsumerWidget {
  final String userId;

  const GroupInstanceTimeline({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allInstances = ref.watch(groupMonitorSortedInstancesProvider(userId));
    final allGroupsById = ref.watch(groupMonitorAllGroupsByIdProvider(userId));
    final newestInstanceId = ref.watch(
      groupMonitorProvider(userId).select((state) => state.newestInstanceId),
    );
    final hasSelectedGroups = ref.watch(
      groupMonitorProvider(
        userId,
      ).select((state) => state.selectedGroupIds.isNotEmpty),
    );
    final hasErrors = ref.watch(
      groupMonitorProvider(
        userId,
      ).select((state) => state.groupErrors.isNotEmpty),
    );
    final hasIncompleteCooldownData = ref.watch(
      groupMonitorHasIncompleteCooldownDataProvider(userId),
    );

    if (allInstances.isEmpty) {
      if (hasSelectedGroups && !hasErrors && hasIncompleteCooldownData) {
        return const LoadingState(
          semanticLabel: 'Loading instances',
          message: 'Loading instances...',
        );
      }

      return GroupInstancesEmptyState(
        hasSelectedGroups: hasSelectedGroups,
        hasErrors: hasErrors,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: allInstances.length,
      itemBuilder: (context, index) {
        final instanceWithGroup = allInstances[index];
        final group =
            allGroupsById[instanceWithGroup.groupId] ?? LimitedUserGroups();
        final isLast = index == allInstances.length - 1;
        final isNewest =
            instanceWithGroup.instance.instanceId == newestInstanceId;

        return AnimatedFadeSlide(
          key: ValueKey((
            instanceWithGroup.groupId,
            instanceWithGroup.instance.instanceId,
            instanceWithGroup.firstDetectedAt,
          )),
          child: InstanceTimelineItem(
            instanceWithGroup: instanceWithGroup,
            group: group,
            isFirst: index == 0,
            isLast: isLast,
            isNewest: isNewest,
          ),
        );
      },
    );
  }
}
