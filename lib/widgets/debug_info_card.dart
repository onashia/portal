import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import '../providers/api_call_counter.dart';
import '../providers/group_monitor_provider.dart';

class DebugInfoCard extends ConsumerWidget {
  final GroupMonitorState monitorState;

  const DebugInfoCard({super.key, required this.monitorState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiCallState = ref.watch(apiCallCounterProvider);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                SizedBox(width: context.m3e.spacing.sm),
                Text(
                  'Debug Info',
                  style: context.m3e.typography.base.titleMedium,
                ),
              ],
            ),
            SizedBox(height: context.m3e.spacing.md),
            Text(
              'Monitoring: ${monitorState.isMonitoring}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'Selected Groups: ${monitorState.selectedGroupIds.length}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'Total Instances: ${monitorState.groupInstances.values.fold<int>(0, (sum, list) => sum + list.length)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'API Calls: ${apiCallState.totalCalls}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (monitorState.groupErrors.isNotEmpty) ...[
              SizedBox(height: context.m3e.spacing.md),
              Text(
                'Errors: ${monitorState.groupErrors.length}',
                style: context.m3e.typography.base.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              SizedBox(height: context.m3e.spacing.sm),
              for (final entry in monitorState.groupErrors.entries)
                Padding(
                  padding: EdgeInsets.only(top: context.m3e.spacing.xs),
                  child: Text(
                    '• ${_getGroupName(monitorState, entry.key)}: ${entry.value}',
                    style: context.m3e.typography.base.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            if (monitorState.groupInstances.isNotEmpty &&
                monitorState.groupInstances.values.every(
                  (list) => list.isEmpty,
                ))
              Padding(
                padding: EdgeInsets.only(top: context.m3e.spacing.md),
                child: Text(
                  'All groups returned empty instance lists',
                  style: context.m3e.typography.base.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getGroupName(GroupMonitorState state, String groupId) {
    try {
      final group = state.allGroups.firstWhere((g) => g.groupId == groupId);
      return group.name ?? groupId.substring(0, 8);
    } catch (_) {
      return groupId.substring(0, 8);
    }
  }
}
