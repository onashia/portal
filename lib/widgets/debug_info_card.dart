import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../providers/api_call_counter.dart';
import '../providers/group_monitor_provider.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../utils/date_time_utils.dart';
import '../utils/group_utils.dart';

class DebugInfoCard extends ConsumerWidget {
  const DebugInfoCard({super.key, required this.userId, this.useCard = true});

  final String userId;
  final bool useCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(groupMonitorProvider(userId));
    final apiCallState = ref.watch(apiCallCounterProvider);
    final m3e = context.m3e;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final coreRows = _buildCoreMetricRows(monitorState, apiCallState);
    final boostRows = _buildBoostMetricRows(monitorState);
    final relayRows = _buildRelayMetricRows(monitorState);
    final labelStyle = textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final valueStyle = textTheme.bodyMedium;
    final errorStyle = textTheme.bodyMedium?.copyWith(color: scheme.error);

    final content = Padding(
      padding: EdgeInsets.all(m3e.spacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            SizedBox(height: m3e.spacing.sm),
            for (final row in coreRows)
              _buildMetricRow(
                context,
                row,
                labelStyle: labelStyle,
                valueStyle: valueStyle,
              ),
            SizedBox(height: m3e.spacing.sm),
            for (final row in boostRows)
              _buildMetricRow(
                context,
                row,
                labelStyle: labelStyle,
                valueStyle: valueStyle,
              ),
            SizedBox(height: m3e.spacing.sm),
            for (final row in relayRows)
              _buildMetricRow(
                context,
                row,
                labelStyle: labelStyle,
                valueStyle: valueStyle,
              ),
            _buildErrorSection(context, monitorState, errorStyle: errorStyle),
            _buildAllGroupsEmptyNotice(
              context,
              monitorState,
              errorStyle: errorStyle,
            ),
          ],
        ),
      ),
    );

    if (!useCard) {
      return content;
    }
    return Card(child: content);
  }

  Widget _buildHeader(BuildContext context) {
    final m3e = context.m3e;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          Icons.bug_report_outlined,
          size: 20,
          color: theme.colorScheme.primary,
        ),
        SizedBox(width: m3e.spacing.sm),
        Expanded(
          child: Text(
            'Debug Info',
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  List<_MetricRowData> _buildCoreMetricRows(
    GroupMonitorState monitorState,
    ApiCallCounterState apiCallState,
  ) {
    return [
      _MetricRowData('Monitoring', monitorState.isMonitoring.toString()),
      _MetricRowData(
        'Selected Groups',
        monitorState.selectedGroupIds.length.toString(),
      ),
      _MetricRowData(
        'Total Instances',
        monitorState.groupInstances.values
            .fold<int>(0, (sum, list) => sum + list.length)
            .toString(),
      ),
      _MetricRowData('API Calls', apiCallState.totalCalls.toString()),
      _MetricRowData('Throttled Skips', apiCallState.throttledSkips.toString()),
      ..._buildApiLaneMetrics(apiCallState),
    ];
  }

  List<_MetricRowData> _buildBoostMetricRows(GroupMonitorState monitorState) {
    return [
      _MetricRowData('Boost Active', monitorState.isBoostActive.toString()),
      _MetricRowData(
        'Boost Group',
        monitorState.boostedGroupId == null
            ? '—'
            : _getGroupName(monitorState, monitorState.boostedGroupId!),
      ),
      _MetricRowData(
        'Boost Expires In',
        _formatDuration(
          monitorState.boostExpiresAt?.difference(DateTime.now()),
        ),
      ),
      _MetricRowData('Boost Polls', monitorState.boostPollCount.toString()),
      _MetricRowData(
        'Boost Last Latency',
        monitorState.lastBoostLatencyMs == null
            ? '—'
            : '${monitorState.lastBoostLatencyMs} ms',
      ),
      _MetricRowData(
        'Boost Last FetchedAt',
        _formatDateTime(monitorState.lastBoostFetchedAt),
      ),
      _MetricRowData(
        'Boost First Seen After',
        _formatDuration(monitorState.boostFirstSeenAfter),
      ),
    ];
  }

  List<_MetricRowData> _buildRelayMetricRows(GroupMonitorState monitorState) {
    return [
      _MetricRowData(
        'Relay Enabled',
        monitorState.relayAssistEnabled.toString(),
      ),
      _MetricRowData('Relay Connected', monitorState.relayConnected.toString()),
      _MetricRowData(
        'Relay Hints Sent',
        monitorState.relayHintsPublished.toString(),
      ),
      _MetricRowData(
        'Relay Hints Received',
        monitorState.relayHintsReceived.toString(),
      ),
      _MetricRowData(
        'Relay Last Hint',
        _formatDateTime(monitorState.lastRelayHintAt),
      ),
      _MetricRowData(
        'Relay Disabled Until',
        _formatDateTime(monitorState.relayTemporarilyDisabledUntil),
      ),
      _MetricRowData('Relay Last Error', monitorState.lastRelayError ?? '—'),
    ];
  }

  List<_MetricRowData> _buildApiLaneMetrics(ApiCallCounterState apiCallState) {
    return ApiRequestLane.values
        .map(
          (lane) => _MetricRowData(
            'API Lane ${lane.name}',
            (apiCallState.callsByLane[lane.name] ?? 0).toString(),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildErrorSection(
    BuildContext context,
    GroupMonitorState monitorState, {
    required TextStyle? errorStyle,
  }) {
    if (monitorState.groupErrors.isEmpty) {
      return const SizedBox.shrink();
    }

    final m3e = context.m3e;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: m3e.spacing.md),
        Text('Errors: ${monitorState.groupErrors.length}', style: errorStyle),
        SizedBox(height: m3e.spacing.sm),
        for (final entry in monitorState.groupErrors.entries)
          Padding(
            padding: EdgeInsets.only(top: m3e.spacing.xs),
            child: Text(
              '• ${_getGroupName(monitorState, entry.key)}: ${entry.value}',
              style: errorStyle,
            ),
          ),
      ],
    );
  }

  Widget _buildAllGroupsEmptyNotice(
    BuildContext context,
    GroupMonitorState monitorState, {
    required TextStyle? errorStyle,
  }) {
    final allGroupsEmpty =
        monitorState.groupInstances.isNotEmpty &&
        monitorState.groupInstances.values.every((list) => list.isEmpty);
    if (!allGroupsEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: context.m3e.spacing.md),
      child: Text(
        'All groups returned empty instance lists',
        style: errorStyle,
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context,
    _MetricRowData row, {
    required TextStyle? labelStyle,
    required TextStyle? valueStyle,
  }) {
    final m3e = context.m3e;

    return Padding(
      padding: EdgeInsets.only(top: m3e.spacing.xs),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedLayout = constraints.maxWidth < 240;
          if (useStackedLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: m3e.spacing.xs),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    row.value,
                    style: valueStyle,
                    textAlign: TextAlign.right,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  row.label,
                  style: labelStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: m3e.spacing.sm),
              Flexible(
                flex: 4,
                child: Text(
                  row.value,
                  style: valueStyle,
                  textAlign: TextAlign.right,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getGroupName(GroupMonitorState state, String groupId) {
    try {
      final group = state.allGroups.firstWhere((g) => g.groupId == groupId);
      return group.name ?? GroupUtils.getShortGroupId(groupId);
    } catch (_) {
      return GroupUtils.getShortGroupId(groupId);
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) {
      return '—';
    }

    final totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) {
      return '00:00';
    }

    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '—';
    }
    return DateTimeUtils.formatLocalJms(value);
  }
}

class _MetricRowData {
  const _MetricRowData(this.label, this.value);

  final String label;
  final String value;
}
