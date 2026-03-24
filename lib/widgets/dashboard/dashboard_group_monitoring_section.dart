import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../providers/group_monitor_provider.dart';
import '../group_instance_list.dart';
import 'dashboard_section_card.dart';
import 'selected_group_chip.dart';

class DashboardGroupMonitoringSection extends ConsumerWidget {
  final String userId;

  const DashboardGroupMonitoringSection({super.key, required this.userId});

  void _toggleBoostForGroup(WidgetRef ref, String? groupId) {
    if (groupId != null) {
      ref
          .read(groupMonitorProvider(userId).notifier)
          .toggleBoostForGroup(groupId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorMeta = ref.watch(
      groupMonitorProvider(userId).select(
        (state) => (
          boostedGroupId: state.boostedGroupId,
          isBoostActive: state.isBoostActive,
          isMonitoring: state.isMonitoring,
          groupErrors: state.groupErrors,
        ),
      ),
    );
    final selectedGroups = ref.watch(
      groupMonitorSelectedGroupsProvider(userId),
    );
    final instanceCount = ref.watch(groupMonitorInstanceCountProvider(userId));
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Active Instances',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: context.m3e.spacing.xs),
              Text(
                '$instanceCount active instance${instanceCount == 1 ? '' : 's'}',
                style: labelStyle,
              ),
            ],
          ),
          SizedBox(height: context.m3e.spacing.lg),
          Expanded(child: GroupInstanceList(userId: userId)),
          SizedBox(height: context.m3e.spacing.md),
          const Divider(),
          SizedBox(height: context.m3e.spacing.sm),
          Row(
            children: [
              Text('Selected Groups', style: labelStyle),
              SizedBox(width: context.m3e.spacing.sm),
              Text('\u2022', style: labelStyle),
              SizedBox(width: context.m3e.spacing.sm),
              Text(selectedGroups.length.toString(), style: labelStyle),
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
                          monitorMeta.boostedGroupId == group.groupId &&
                          monitorMeta.isBoostActive,
                      hasError:
                          group.groupId != null &&
                          monitorMeta.groupErrors.containsKey(group.groupId),
                      errorMessage: group.groupId == null
                          ? null
                          : monitorMeta.groupErrors[group.groupId],
                      isMonitoring: monitorMeta.isMonitoring,
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
    );
  }
}
