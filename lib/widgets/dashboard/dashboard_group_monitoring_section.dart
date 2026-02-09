import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../providers/group_monitor_provider.dart';
import '../group_instance_list.dart';
import 'selected_group_chip.dart';

class DashboardGroupMonitoringSection extends ConsumerWidget {
  final String userId;
  final GroupMonitorState monitorState;
  final List<LimitedUserGroups> selectedGroups;

  const DashboardGroupMonitoringSection({
    super.key,
    required this.userId,
    required this.monitorState,
    required this.selectedGroups,
  });

  void _toggleBoostForGroup(WidgetRef ref, String? groupId) {
    if (groupId != null) {
      ref
          .read(groupMonitorProvider(userId).notifier)
          .toggleBoostForGroup(groupId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cardTheme = Theme.of(context).cardTheme;
    final baseShape =
        cardTheme.shape as RoundedRectangleBorder? ??
        RoundedRectangleBorder(borderRadius: context.m3e.shapes.round.md);
    final outlineColor = scheme.outlineVariant.withValues(alpha: 0.4);

    return Card(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: baseShape.copyWith(side: BorderSide(color: outlineColor)),
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group Monitoring',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: context.m3e.spacing.md),
            Expanded(
              child: GroupInstanceList(
                userId: userId,
                scrollable: true,
                onRefresh: () {
                  ref
                      .read(groupMonitorProvider(userId).notifier)
                      .fetchGroupInstances();
                },
              ),
            ),
            SizedBox(height: context.m3e.spacing.md),
            Divider(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            SizedBox(height: context.m3e.spacing.sm),
            Row(
              children: [
                Text(
                  'Selected Groups',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: context.m3e.spacing.sm),
                Text(
                  '\u2022',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: context.m3e.spacing.sm),
                Text(
                  selectedGroups.length.toString(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (selectedGroups.isNotEmpty) ...[
              SizedBox(height: context.m3e.spacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final group in selectedGroups) ...[
                      SelectedGroupChip(
                        group: group,
                        isBoosted:
                            monitorState.boostedGroupId == group.groupId &&
                            monitorState.isBoostActive,
                        isMonitoring: monitorState.isMonitoring,
                        onToggleBoost: () =>
                            _toggleBoostForGroup(ref, group.groupId),
                      ),
                      SizedBox(width: context.m3e.spacing.sm),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
