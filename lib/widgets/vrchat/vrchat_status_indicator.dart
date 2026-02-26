import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../constants/icon_sizes.dart';
import '../../constants/ui_constants.dart';
import '../../models/vrchat_status.dart';
import '../../providers/vrchat_status_provider.dart';
import '../../theme/vrchat_status_colors.dart';
import '../../utils/timing_utils.dart';

class VrchatStatusWidget extends ConsumerWidget {
  const VrchatStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusState = ref.watch(vrchatStatusProvider);
    final state = statusState.value;

    return _VrchatStatusCompactView(
      state: state,
      onTap: () => _showStatusDialog(context, state),
    );
  }

  void _showStatusDialog(BuildContext context, VrchatStatusState? state) {
    if (state == null || state.status == null) {
      return;
    }

    final status = state.status!;
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('VRChat Status'),
        contentPadding: EdgeInsets.all(context.m3e.spacing.lg),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: UiConstants.vrchatStatusDialogMaxWidth,
          ),
          child: SingleChildScrollView(
            child: _VrchatStatusDialogContent(
              status: status,
              statusColor: _statusColorForIndicator(status.indicator, scheme),
            ),
          ),
        ),
        actions: [
          ButtonM3E(
            onPressed: () => Navigator.of(context).pop(),
            label: const Text('Close'),
            style: ButtonM3EStyle.text,
            size: ButtonM3ESize.sm,
            shape: ButtonM3EShape.square,
          ),
        ],
      ),
    );
  }
}

class _VrchatStatusCompactView extends StatelessWidget {
  const _VrchatStatusCompactView({required this.state, required this.onTap});

  final VrchatStatusState? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m3e.spacing.md,
          vertical: m3e.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: m3e.shapes.round.sm,
        ),
        child: _buildCompactContent(context, scheme, textTheme, m3e),
      ),
    );
  }

  Widget _buildCompactContent(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
    M3ETheme m3e,
  ) {
    if (state == null || state!.isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: m3e.spacing.md,
        children: [
          SizedBox(
            width: UiConstants.vrchatCompactLoaderSize,
            height: UiConstants.vrchatCompactLoaderSize,
            child: const CircularProgressIndicator(
              strokeWidth: UiConstants.vrchatCompactLoaderStrokeWidth,
            ),
          ),
          Text('Loading...', style: textTheme.bodySmall),
        ],
      );
    }

    if (state!.errorMessage != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: m3e.spacing.md,
        children: [
          Icon(Icons.error_outline, size: IconSizes.xxs, color: scheme.error),
          Text(
            'Error',
            style: textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      );
    }

    final status = state!.status!;
    final statusColor = _statusColorForIndicator(status.indicator, scheme);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: UiConstants.vrchatStatusDotSize,
          height: UiConstants.vrchatStatusDotSize,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        SizedBox(width: m3e.spacing.md),
        Flexible(
          child: Text(
            status.description,
            style: textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (status.activeIncidents.isNotEmpty) ...[
          SizedBox(width: m3e.spacing.sm),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: m3e.spacing.xs,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: m3e.shapes.round.md,
            ),
            child: Text(
              '${status.activeIncidents.length}',
              style: textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _VrchatStatusDialogContent extends StatelessWidget {
  const _VrchatStatusDialogContent({
    required this.status,
    required this.statusColor,
  });

  final VrchatStatus status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final statusColors = Theme.of(context).extension<VrchatStatusColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildOverallStatus(context, textTheme, m3e),
        SizedBox(height: m3e.spacing.lg),
        _buildServicesSection(context, textTheme, m3e, statusColors),
        if (status.activeIncidents.isNotEmpty) ...[
          SizedBox(height: m3e.spacing.md),
          _buildIncidentsSection(context, textTheme, scheme, m3e),
        ],
        SizedBox(height: m3e.spacing.md),
        Text(
          'Last updated: ${TimingUtils.formatRelativeTimeVerbose(status.lastUpdated)}',
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildOverallStatus(
    BuildContext context,
    TextTheme textTheme,
    M3ETheme m3e,
  ) {
    return Container(
      padding: EdgeInsets.all(m3e.spacing.md),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: m3e.shapes.round.sm,
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        spacing: m3e.spacing.md,
        children: [
          Icon(
            _statusIconForIndicator(status.indicator),
            color: statusColor,
            size: IconSizes.sm,
          ),
          Expanded(
            child: Text(
              status.description,
              style: textTheme.titleMedium?.copyWith(
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
    TextTheme textTheme,
    M3ETheme m3e,
    VrchatStatusColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, group) in status.serviceGroups.indexed) ...[
          _buildServiceGroup(context, group, textTheme, m3e, colors),
          if (index < status.serviceGroups.length - 1)
            SizedBox(height: m3e.spacing.md),
        ],
      ],
    );
  }

  Widget _buildServiceGroup(
    BuildContext context,
    VrchatServiceGroup group,
    TextTheme textTheme,
    M3ETheme m3e,
    VrchatStatusColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: m3e.spacing.xs),
          child: Text(
            group.name,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ...group.services.map(
          (service) => Padding(
            padding: EdgeInsets.only(left: m3e.spacing.lg),
            child: _buildServiceItem(context, service, textTheme, m3e, colors),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceItem(
    BuildContext context,
    VrchatServiceStatus service,
    TextTheme textTheme,
    M3ETheme m3e,
    VrchatStatusColors colors,
  ) {
    final serviceColor = _serviceStatusColor(service.status, colors);
    final isOperational = service.status.toLowerCase() == 'operational';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m3e.spacing.xs),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: serviceColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: m3e.spacing.md),
          Expanded(child: Text(service.name, style: textTheme.bodyMedium)),
          SizedBox(width: m3e.spacing.xxl),
          Text(
            service.status,
            style: textTheme.bodySmall?.copyWith(
              color: isOperational
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : serviceColor,
              fontWeight: isOperational ? FontWeight.normal : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncidentsSection(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme scheme,
    M3ETheme m3e,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Incidents (${status.activeIncidents.length})',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: m3e.spacing.sm),
        for (final (index, incident) in status.activeIncidents.indexed) ...[
          _buildIncidentItem(context, incident, textTheme, scheme, m3e),
          if (index < status.activeIncidents.length - 1)
            SizedBox(height: m3e.spacing.sm),
        ],
      ],
    );
  }

  Widget _buildIncidentItem(
    BuildContext context,
    Incident incident,
    TextTheme textTheme,
    ColorScheme scheme,
    M3ETheme m3e,
  ) {
    final latestUpdate = incident.updates.isNotEmpty
        ? incident.updates.first
        : null;
    final incidentColor = _incidentStatusColor(incident.status, scheme);
    final incidentContentIndent = IconSizes.xxs + m3e.spacing.md;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(m3e.spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: m3e.spacing.md,
              children: [
                Icon(
                  _incidentStatusIcon(incident.status),
                  size: IconSizes.xxs,
                  color: incidentColor,
                ),
                Expanded(
                  child: Text(
                    incident.name,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: m3e.spacing.sm),
            Padding(
              padding: EdgeInsets.only(left: incidentContentIndent),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _incidentStatusLabel(incident.status),
                    style: textTheme.labelSmall?.copyWith(
                      color: incidentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (latestUpdate != null) ...[
                    SizedBox(height: m3e.spacing.xs),
                    Text(
                      latestUpdate.body,
                      style: textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: m3e.spacing.xs),
                    Text(
                      TimingUtils.formatRelativeTimeVerbose(
                        latestUpdate.createdAt,
                      ),
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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
}

Color _statusColorForIndicator(
  VrchatStatusIndicator indicator,
  ColorScheme scheme,
) {
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

IconData _statusIconForIndicator(VrchatStatusIndicator indicator) {
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

Color _serviceStatusColor(String status, VrchatStatusColors colors) {
  final normalized = status.toLowerCase();
  if (normalized == 'operational') {
    return colors.operational;
  }
  if (normalized == 'degraded_performance') {
    return colors.degraded;
  }
  return colors.outage;
}

String _incidentStatusLabel(IncidentStatus status) {
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

IconData _incidentStatusIcon(IncidentStatus status) {
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

Color _incidentStatusColor(IncidentStatus status, ColorScheme scheme) {
  switch (status) {
    case IncidentStatus.investigating:
      return scheme.tertiary;
    case IncidentStatus.identified:
      return scheme.primary;
    case IncidentStatus.monitoring:
      return scheme.secondary;
    case IncidentStatus.resolved:
      return scheme.primary;
  }
}
