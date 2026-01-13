import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        padding: const EdgeInsets.all(16),
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
                const SizedBox(width: 8),
                Text(
                  'Debug Info',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Text(
                'Errors: ${monitorState.groupErrors.length}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in monitorState.groupErrors.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${_getGroupName(monitorState, entry.key)}: ${entry.value}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'All groups returned empty instance lists',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
    final group = state.allGroups.firstWhere(
      (g) => g.groupId == groupId,
      orElse: () => throw Exception('Group not found'),
    );
    return group.name ?? groupId.substring(0, 8);
  }
}
