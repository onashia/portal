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

  static const double _stackedLayoutBreakpoint = 360.0;

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
    final monitoringRows = _buildMonitoringMetricRows(
      monitorState,
      apiCallState,
    );
    final apiLanesRows = _buildApiLanesMetricRows(apiCallState);
    final boostRows = _buildBoostMetricRows(monitorState);
    final relayRows = _buildRelayMetricRows(monitorState);
    final labelStyle = textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final valueStyle = textTheme.bodyMedium;
    final errorStyle = textTheme.bodyMedium?.copyWith(color: scheme.error);

    final content = Padding(
      padding: EdgeInsets.all(m3e.spacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStackedLayout =
              constraints.maxWidth < _stackedLayoutBreakpoint;

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                SizedBox(height: m3e.spacing.md),
                if (useStackedLayout) ...[
                  _buildSection(
                    context,
                    'Monitoring',
                    monitoringRows,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                  SizedBox(height: m3e.spacing.lg),
                  _buildSection(
                    context,
                    'Boost',
                    boostRows,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                  SizedBox(height: m3e.spacing.lg),
                  _buildSection(
                    context,
                    'API Lanes',
                    apiLanesRows,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                  SizedBox(height: m3e.spacing.lg),
                  _buildSection(
                    context,
                    'Relay',
                    relayRows,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSection(
                              context,
                              'Monitoring',
                              monitoringRows,
                              labelStyle: labelStyle,
                              valueStyle: valueStyle,
                            ),
                            SizedBox(height: m3e.spacing.lg),
                            _buildSection(
                              context,
                              'Boost',
                              boostRows,
                              labelStyle: labelStyle,
                              valueStyle: valueStyle,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: m3e.spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSection(
                              context,
                              'API Lanes',
                              apiLanesRows,
                              labelStyle: labelStyle,
                              valueStyle: valueStyle,
                            ),
                            SizedBox(height: m3e.spacing.lg),
                            _buildSection(
                              context,
                              'Relay',
                              relayRows,
                              labelStyle: labelStyle,
                              valueStyle: valueStyle,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                _buildErrorSection(
                  context,
                  monitorState,
                  errorStyle: errorStyle,
                ),
                _buildAllGroupsEmptyNotice(
                  context,
                  monitorState,
                  errorStyle: errorStyle,
                ),
              ],
            ),
          );
        },
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

  Widget _buildSection(
    BuildContext context,
    String title,
    List<_MetricRowData> rows, {
    required TextStyle? labelStyle,
    required TextStyle? valueStyle,
  }) {
    final m3e = context.m3e;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        Divider(height: m3e.spacing.md),
        for (final row in rows)
          _buildMetricRow(
            context,
            row,
            labelStyle: labelStyle,
            valueStyle: valueStyle,
          ),
      ],
    );
  }

  List<_MetricRowData> _buildMonitoringMetricRows(
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
      _MetricRowData('Auto Invite', monitorState.autoInviteEnabled.toString()),
    ];
  }

  List<_MetricRowData> _buildApiLanesMetricRows(
    ApiCallCounterState apiCallState,
  ) {
    return ApiRequestLane.values
        .map(
          (lane) => _MetricRowData(
            lane.name,
            (apiCallState.callsByLane[lane.name] ?? 0).toString(),
          ),
        )
        .toList(growable: false);
  }

  List<_MetricRowData> _buildBoostMetricRows(GroupMonitorState monitorState) {
    return [
      _MetricRowData('Active', monitorState.isBoostActive.toString()),
      _MetricRowData(
        'Group',
        monitorState.boostedGroupId == null
            ? '—'
            : _getGroupName(monitorState, monitorState.boostedGroupId!),
      ),
      _MetricRowData(
        'Expires In',
        _formatDuration(
          monitorState.boostExpiresAt?.difference(DateTime.now()),
        ),
      ),
      _MetricRowData('Polls', monitorState.boostPollCount.toString()),
      _MetricRowData(
        'Last Latency',
        monitorState.lastBoostLatencyMs == null
            ? '—'
            : '${monitorState.lastBoostLatencyMs} ms',
      ),
      _MetricRowData(
        'Last FetchedAt',
        _formatDateTime(monitorState.lastBoostFetchedAt),
      ),
      _MetricRowData(
        'First Seen After',
        _formatDuration(monitorState.boostFirstSeenAfter),
      ),
    ];
  }

  List<_MetricRowData> _buildRelayMetricRows(GroupMonitorState monitorState) {
    return [
      _MetricRowData('Enabled', monitorState.relayAssistEnabled.toString()),
      _MetricRowData('Connected', monitorState.relayConnected.toString()),
      _MetricRowData('Hints Sent', monitorState.relayHintsPublished.toString()),
      _MetricRowData(
        'Hints Received',
        monitorState.relayHintsReceived.toString(),
      ),
      _MetricRowData(
        'Last Hint',
        _formatDateTime(monitorState.lastRelayHintAt),
      ),
      _MetricRowData(
        'Disabled Until',
        _formatDateTime(monitorState.relayTemporarilyDisabledUntil),
      ),
      _MetricRowData('Last Error', monitorState.lastRelayError ?? '—'),
    ];
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              row.label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: m3e.spacing.sm),
          Flexible(
            flex: 2,
            child: Text(
              row.value,
              style: valueStyle,
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
