import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../constants/icon_sizes.dart';
import '../../constants/ui_constants.dart';
import '../../models/vrchat_status.dart';
import '../../theme/vrchat_status_colors.dart';
import '../../utils/timing_utils.dart';
import 'vrchat_status_visuals.dart';

Future<void> showVrchatStatusDialog(BuildContext context, VrchatStatus status) {
  final scheme = Theme.of(context).colorScheme;

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('VRChat Status'),
      contentPadding: EdgeInsets.fromLTRB(
        context.m3e.spacing.xl,
        context.m3e.spacing.lg,
        context.m3e.spacing.xl,
        context.m3e.spacing.lg,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: UiConstants.vrchatStatusDialogMaxWidth,
        ),
        child: SingleChildScrollView(
          child: VrchatStatusDialogContent(
            status: status,
            statusColor: statusColorForIndicator(status.indicator, scheme),
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

class VrchatStatusDialogContent extends StatelessWidget {
  const VrchatStatusDialogContent({
    super.key,
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
        _OverallStatusBanner(
          status: status,
          statusColor: statusColor,
          textTheme: textTheme,
        ),
        SizedBox(height: m3e.spacing.lg),
        _ServiceGroupsSection(
          groups: status.serviceGroups,
          textTheme: textTheme,
          colors: statusColors,
        ),
        if (status.activeIncidents.isNotEmpty) ...[
          SizedBox(height: m3e.spacing.md),
          _IncidentsSection(
            incidents: status.activeIncidents,
            textTheme: textTheme,
            scheme: scheme,
          ),
        ],
        SizedBox(height: m3e.spacing.md),
        Text(
          'Last updated: ${TimingUtils.formatRelativeTimeVerbose(status.lastUpdated)}',
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _OverallStatusBanner extends StatelessWidget {
  const _OverallStatusBanner({
    required this.status,
    required this.statusColor,
    required this.textTheme,
  });

  final VrchatStatus status;
  final Color statusColor;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;

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
            statusIconForIndicator(status.indicator),
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
}

class _ServiceGroupsSection extends StatelessWidget {
  const _ServiceGroupsSection({
    required this.groups,
    required this.textTheme,
    required this.colors,
  });

  final List<VrchatServiceGroup> groups;
  final TextTheme textTheme;
  final VrchatStatusColors colors;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, group) in groups.indexed) ...[
          _ServiceGroupSection(
            group: group,
            textTheme: textTheme,
            colors: colors,
          ),
          if (index < groups.length - 1) SizedBox(height: m3e.spacing.md),
        ],
      ],
    );
  }
}

class _ServiceGroupSection extends StatelessWidget {
  const _ServiceGroupSection({
    required this.group,
    required this.textTheme,
    required this.colors,
  });

  final VrchatServiceGroup group;
  final TextTheme textTheme;
  final VrchatStatusColors colors;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;

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
            child: _ServiceStatusRow(
              service: service,
              textTheme: textTheme,
              colors: colors,
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceStatusRow extends StatelessWidget {
  const _ServiceStatusRow({
    required this.service,
    required this.textTheme,
    required this.colors,
  });

  final VrchatServiceStatus service;
  final TextTheme textTheme;
  final VrchatStatusColors colors;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;
    final scheme = Theme.of(context).colorScheme;
    final color = serviceStatusColor(service.status, colors);
    final isOperational = service.status.toLowerCase() == 'operational';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: m3e.spacing.xs),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: m3e.spacing.md),
          Expanded(child: Text(service.name, style: textTheme.bodyMedium)),
          SizedBox(width: m3e.spacing.xxl),
          Text(
            service.status,
            style: textTheme.bodySmall?.copyWith(
              color: isOperational ? scheme.onSurfaceVariant : color,
              fontWeight: isOperational ? FontWeight.normal : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _IncidentsSection extends StatelessWidget {
  const _IncidentsSection({
    required this.incidents,
    required this.textTheme,
    required this.scheme,
  });

  final List<Incident> incidents;
  final TextTheme textTheme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Active Incidents (${incidents.length})',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: m3e.spacing.sm),
        for (final (index, incident) in incidents.indexed) ...[
          _IncidentCard(
            incident: incident,
            textTheme: textTheme,
            scheme: scheme,
          ),
          if (index < incidents.length - 1) SizedBox(height: m3e.spacing.sm),
        ],
      ],
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    required this.incident,
    required this.textTheme,
    required this.scheme,
  });

  final Incident incident;
  final TextTheme textTheme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final latestUpdate = incident.updates.isNotEmpty
        ? incident.updates.first
        : null;
    final color = incidentStatusColor(incident.status, scheme);
    final m3e = context.m3e;
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
                  incidentStatusIcon(incident.status),
                  size: IconSizes.xxs,
                  color: color,
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
                    incidentStatusLabel(incident.status),
                    style: textTheme.labelSmall?.copyWith(
                      color: color,
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
