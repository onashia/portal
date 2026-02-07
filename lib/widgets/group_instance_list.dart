import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/group_monitor_provider.dart';
import 'group_instances/group_instances_empty_state.dart';
import 'group_instances/group_instances_section.dart';

class GroupInstanceList extends ConsumerWidget {
  final String userId;
  final VoidCallback onRefresh;
  final bool scrollable;

  const GroupInstanceList({
    super.key,
    required this.userId,
    required this.onRefresh,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(groupMonitorProvider(userId));

    final groupsWithInstances = monitorState.groupInstances.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList();

    if (groupsWithInstances.isEmpty) {
      return GroupInstancesEmptyState(state: monitorState);
    }

    if (!scrollable) {
      return Column(
        children: [
          for (var i = 0; i < groupsWithInstances.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GroupInstancesSection(
                group: monitorState.allGroups.firstWhere(
                  (g) => g.groupId == groupsWithInstances[i].key,
                  orElse: () => LimitedUserGroups(),
                ),
                instances: groupsWithInstances[i].value,
                newInstances: monitorState.newInstances,
                onRefresh: onRefresh,
              ),
            ),
          if (groupsWithInstances.length > 1)
            for (var i = 0; i < groupsWithInstances.length - 1; i++)
              SizedBox(height: context.m3e.spacing.md),
        ],
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final entry = groupsWithInstances[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GroupInstancesSection(
            group: monitorState.allGroups.firstWhere(
              (g) => g.groupId == entry.key,
              orElse: () => LimitedUserGroups(),
            ),
            instances: entry.value,
            newInstances: monitorState.newInstances,
            onRefresh: onRefresh,
          ),
        );
      },
      separatorBuilder: (context, index) =>
          SizedBox(height: context.m3e.spacing.md),
      itemCount: groupsWithInstances.length,
    );
  }
}
