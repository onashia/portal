import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import '../constants/app_typography.dart';
import '../providers/api_call_counter.dart';
import '../providers/group_monitor_provider.dart';

class DebugInfoCard extends ConsumerWidget {
  final GroupMonitorState monitorState;
  final bool useCard;

  const DebugInfoCard({
    super.key,
    required this.monitorState,
    this.useCard = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiCallState = ref.watch(apiCallCounterProvider);

    final content = Padding(
      padding: EdgeInsets.all(context.m3e.spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              Text('Debug Info', style: AppTypography.titleMedium),
            ],
          ),
          SizedBox(height: context.m3e.spacing.sm),
          _buildMetricRow(
            context,
            label: 'Monitoring',
            value: monitorState.isMonitoring.toString(),
          ),
          _buildMetricRow(
            context,
            label: 'Selected Groups',
            value: monitorState.selectedGroupIds.length.toString(),
          ),
          _buildMetricRow(
            context,
            label: 'Total Instances',
            value: monitorState.groupInstances.values
                .fold<int>(0, (sum, list) => sum + list.length)
                .toString(),
          ),
          _buildMetricRow(
            context,
            label: 'API Calls',
            value: apiCallState.totalCalls.toString(),
          ),
          SizedBox(height: context.m3e.spacing.sm),
          _buildMetricRow(
            context,
            label: 'Boost Active',
            value: monitorState.isBoostActive.toString(),
          ),
          _buildMetricRow(
            context,
            label: 'Boost Group',
            value: monitorState.boostedGroupId == null
                ? '—'
                : _getGroupName(monitorState, monitorState.boostedGroupId!),
          ),
          _buildMetricRow(
            context,
            label: 'Boost Expires In',
            value: _formatDuration(
              monitorState.boostExpiresAt?.difference(DateTime.now()),
            ),
          ),
          _buildMetricRow(
            context,
            label: 'Boost Polls',
            value: monitorState.boostPollCount.toString(),
          ),
          _buildMetricRow(
            context,
            label: 'Boost Last Latency',
            value: monitorState.lastBoostLatencyMs == null
                ? '—'
                : '${monitorState.lastBoostLatencyMs} ms',
          ),
          _buildMetricRow(
            context,
            label: 'Boost Last FetchedAt',
            value: _formatDateTime(monitorState.lastBoostFetchedAt),
          ),
          _buildMetricRow(
            context,
            label: 'Boost First Seen After',
            value: _formatDuration(monitorState.boostFirstSeenAfter),
          ),
          if (monitorState.groupErrors.isNotEmpty) ...[
            SizedBox(height: context.m3e.spacing.md),
            Text(
              'Errors: ${monitorState.groupErrors.length}',
              style: AppTypography.bodyMedium.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            SizedBox(height: context.m3e.spacing.sm),
            for (final entry in monitorState.groupErrors.entries)
              Padding(
                padding: EdgeInsets.only(top: context.m3e.spacing.xs),
                child: Text(
                  '• ${_getGroupName(monitorState, entry.key)}: ${entry.value}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
          if (monitorState.groupInstances.isNotEmpty &&
              monitorState.groupInstances.values.every((list) => list.isEmpty))
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
    );

    if (!useCard) return content;
    return Card(child: content);
  }

  String _getGroupName(GroupMonitorState state, String groupId) {
    try {
      final group = state.allGroups.firstWhere((g) => g.groupId == groupId);
      return group.name ?? groupId.substring(0, 8);
    } catch (_) {
      return groupId.substring(0, 8);
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '—';
    final totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) return '00:00';
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '—';
    final hours = value.hour.toString().padLeft(2, '0');
    final minutes = value.minute.toString().padLeft(2, '0');
    final seconds = value.second.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(top: context.m3e.spacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
