import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../models/vrchat_status.dart';
import '../../theme/vrchat_status_colors.dart';
import '../../providers/vrchat_status_provider.dart';
import '../../constants/ui_constants.dart';
import '../../constants/icon_sizes.dart';

class VrchatStatusWidget extends ConsumerWidget {
  const VrchatStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusState = ref.watch(vrchatStatusProvider);
    final statusStateValue = statusState.value;

    return GestureDetector(
      onTap: () => _showStatusDialog(context, statusStateValue),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.m3e.spacing.md,
          vertical: context.m3e.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: context.m3e.shapes.round.sm,
        ),
        child: _buildCompactView(context, statusStateValue),
      ),
    );
  }

  Widget _buildCompactView(BuildContext context, VrchatStatusState? state) {
    if (state == null || state.isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: UiConstants.vrchatCompactLoaderSize,
            height: UiConstants.vrchatCompactLoaderSize,
            child: CircularProgressIndicator(
              strokeWidth: UiConstants.vrchatCompactLoaderStrokeWidth,
            ),
          ),
          SizedBox(width: context.m3e.spacing.md),
          Text('Loading...', style: Theme.of(context).textTheme.bodySmall),
        ],
      );
    }

    if (state.errorMessage != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: IconSizes.xxs,
            color: Theme.of(context).colorScheme.error,
          ),
          SizedBox(width: context.m3e.spacing.md),
          Text(
            'Error',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      );
    }

    final status = state.status!;
    final statusColor = _getStatusColor(status.indicator, context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: UiConstants.vrchatStatusDotSize,
          height: UiConstants.vrchatStatusDotSize,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        SizedBox(width: context.m3e.spacing.md),
        Flexible(
          child: Text(
            status.description,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (status.activeIncidents.isNotEmpty) ...[
          SizedBox(width: context.m3e.spacing.sm),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.m3e.spacing.xs,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: context.m3e.shapes.round.md,
            ),
            child: Text(
              '${status.activeIncidents.length}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _getStatusColor(VrchatStatusIndicator indicator, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (indicator) {
      case VrchatStatusIndicator.none:
        return scheme.primary;
      case VrchatStatusIndicator.minor:
      case VrchatStatusIndicator.major:
        return scheme.tertiary;
      case VrchatStatusIndicator.critical:
        return scheme.error;
    }
  }

  IconData _getStatusIcon(VrchatStatusIndicator indicator) {
    switch (indicator) {
      case VrchatStatusIndicator.none:
        return Icons.check_circle;
      case VrchatStatusIndicator.minor:
        return Icons.warning;
      case VrchatStatusIndicator.major:
        return Icons.error;
      case VrchatStatusIndicator.critical:
        return Icons.error_outline;
    }
  }

  void _showStatusDialog(BuildContext context, VrchatStatusState? state) {
    if (state == null || state.status == null) return;

    final status = state.status!;
    final statusColor = _getStatusColor(status.indicator, context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('VRChat Status'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: UiConstants.vrchatStatusDialogMaxWidth,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildOverallStatus(context, status, statusColor),
                SizedBox(height: context.m3e.spacing.md),
                _buildServicesSection(
                  context,
                  status.serviceGroups,
                  Theme.of(context).extension<VrchatStatusColors>()!,
                ),
                if (status.activeIncidents.isNotEmpty) ...[
                  SizedBox(height: context.m3e.spacing.md),
                  _buildIncidentsSection(context, status.activeIncidents),
                ],
                SizedBox(height: context.m3e.spacing.md),
                _buildLastUpdated(context, status.lastUpdated),
              ],
            ),
          ),
        ),
        actions: [
          ButtonM3E(
            onPressed: () => Navigator.of(context).pop(),
            label: Text('Close'),
            style: ButtonM3EStyle.text,
            size: ButtonM3ESize.sm,
            shape: ButtonM3EShape.square,
          ),
        ],
      ),
    );
  }

  Widget _buildOverallStatus(
    BuildContext context,
    VrchatStatus status,
    Color statusColor,
  ) {
    return Container(
      padding: EdgeInsets.all(context.m3e.spacing.md),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: context.m3e.shapes.round.sm,
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(status.indicator),
            color: statusColor,
            size: IconSizes.sm,
          ),
          SizedBox(width: context.m3e.spacing.md),
          Expanded(
            child: Text(
              status.description,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesSection(
    BuildContext context,
    List<VrchatServiceGroup> serviceGroups,
    VrchatStatusColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...serviceGroups.map(
          (group) => _buildServiceGroup(context, group, colors),
        ),
      ],
    );
  }

  Widget _buildServiceGroup(
    BuildContext context,
    VrchatServiceGroup group,
    VrchatStatusColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: context.m3e.spacing.xs),
          child: Text(
            group.name,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ...group.services.map(
          (service) => Padding(
            padding: EdgeInsets.only(left: context.m3e.spacing.lg),
            child: _buildServiceItem(
              context,
              service.name,
              service.status,
              colors,
            ),
          ),
        ),
        SizedBox(height: context.m3e.spacing.md),
      ],
    );
  }

  Widget _buildServiceItem(
    BuildContext context,
    String name,
    String serviceStatus,
    VrchatStatusColors colors,
  ) {
    final statusColor = _getServiceStatusColor(serviceStatus, colors);
    final isOperational = serviceStatus.toLowerCase() == 'operational';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.m3e.spacing.xs),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: context.m3e.spacing.md),
          Expanded(
            child: Text(name, style: Theme.of(context).textTheme.bodyMedium),
          ),
          SizedBox(width: context.m3e.spacing.xxl),
          Text(
            serviceStatus,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isOperational
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : statusColor,
              fontWeight: isOperational ? FontWeight.normal : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getServiceStatusColor(String status, VrchatStatusColors colors) {
    final normalized = status.toLowerCase();
    if (normalized == 'operational') {
      return colors.operational;
    } else if (normalized == 'degraded_performance') {
      return colors.degraded;
    } else {
      return colors.outage;
    }
  }

  Widget _buildIncidentsSection(
    BuildContext context,
    List<Incident> incidents,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Incidents (${incidents.length})',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: context.m3e.spacing.sm),
        ...incidents.map((incident) => _buildIncidentItem(context, incident)),
      ],
    );
  }

  Widget _buildIncidentItem(BuildContext context, Incident incident) {
    final latestUpdate = incident.updates.isNotEmpty
        ? incident.updates.first
        : null;

    return Card(
      margin: EdgeInsets.only(bottom: context.m3e.spacing.sm),
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getIncidentStatusIcon(incident.status),
                  size: IconSizes.xxs,
                  color: _getIncidentStatusColor(context, incident.status),
                ),
                SizedBox(width: context.m3e.spacing.md),
                Expanded(
                  child: Text(
                    incident.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: context.m3e.spacing.sm),
            Container(
              padding: EdgeInsets.all(context.m3e.spacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: context.m3e.shapes.round.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatIncidentStatus(incident.status),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: _getIncidentStatusColor(context, incident.status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (latestUpdate != null) ...[
                    SizedBox(height: context.m3e.spacing.xs),
                    Text(
                      latestUpdate.body,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: context.m3e.spacing.xs),
                    Text(
                      _formatTimestamp(latestUpdate.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated(BuildContext context, DateTime lastUpdated) {
    final elapsed = DateTime.now().difference(lastUpdated);
    final text = elapsed.inMinutes < 1
        ? 'Just now'
        : elapsed.inHours < 1
        ? '${elapsed.inMinutes} min ago'
        : elapsed.inDays < 1
        ? '${elapsed.inHours} hour${elapsed.inHours > 1 ? 's' : ''} ago'
        : '${elapsed.inDays} day${elapsed.inDays > 1 ? 's' : ''} ago';

    return Text(
      'Last updated: $text',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _formatIncidentStatus(IncidentStatus status) {
    switch (status) {
      case IncidentStatus.investigating:
        return 'Investigating';
      case IncidentStatus.identified:
        return 'Identified';
      case IncidentStatus.monitoring:
        return 'Monitoring';
      case IncidentStatus.resolved:
        return 'Resolved';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final elapsed = now.difference(timestamp);

    if (elapsed.inMinutes < 1) {
      return 'Just now';
    } else if (elapsed.inHours < 1) {
      return '${elapsed.inMinutes} min ago';
    } else if (elapsed.inDays < 1) {
      return '${elapsed.inHours}h ago';
    } else if (elapsed.inDays < 7) {
      return '${elapsed.inDays}d ago';
    } else {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year % 100}';
    }
  }

  IconData _getIncidentStatusIcon(IncidentStatus status) {
    switch (status) {
      case IncidentStatus.investigating:
        return Icons.search;
      case IncidentStatus.identified:
        return Icons.bug_report;
      case IncidentStatus.monitoring:
        return Icons.visibility;
      case IncidentStatus.resolved:
        return Icons.check_circle;
    }
  }

  Color _getIncidentStatusColor(BuildContext context, IncidentStatus status) {
    switch (status) {
      case IncidentStatus.investigating:
        return Theme.of(context).colorScheme.tertiary;
      case IncidentStatus.identified:
        return Theme.of(context).colorScheme.primary;
      case IncidentStatus.monitoring:
        return Theme.of(context).colorScheme.secondary;
      case IncidentStatus.resolved:
        return Theme.of(context).colorScheme.primary;
    }
  }
}
