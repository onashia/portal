import 'package:flutter/material.dart';

import '../../models/vrchat_status.dart';
import '../../theme/vrchat_status_colors.dart';

Color statusColorForIndicator(
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

IconData statusIconForIndicator(VrchatStatusIndicator indicator) {
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

Color serviceStatusColor(String status, VrchatStatusColors colors) {
  final normalized = status.toLowerCase();
  if (normalized == 'operational') {
    return colors.operational;
  }
  if (normalized == 'degraded_performance') {
    return colors.degraded;
  }
  return colors.outage;
}

String incidentStatusLabel(IncidentStatus status) {
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

IconData incidentStatusIcon(IncidentStatus status) {
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

Color incidentStatusColor(IncidentStatus status, ColorScheme scheme) {
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
