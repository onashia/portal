import 'package:dio/dio.dart';
import '../models/vrchat_status.dart';
import '../utils/app_logger.dart';

class VrchatStatusService {
  final Dio _dio;

  VrchatStatusService(this._dio);

  static const String baseUrl = 'https://status.vrchat.com/api/v2';

  Future<VrchatStatus> fetchStatus() async {
    try {
      AppLogger.info('Fetching VRChat status', subCategory: 'vrchat_status');

      final response = await _dio.get('$baseUrl/summary.json');

      final summaryData = response.data as Map<String, dynamic>;

      final indicator = _parseIndicator(summaryData['status']['indicator']);
      final description = summaryData['status']['description'] as String;
      final serviceGroups = _parseComponents(summaryData['components'] as List);
      final incidents = _parseIncidents(summaryData['incidents'] as List);

      final activeIncidents = incidents
          .where((i) => i.status != IncidentStatus.resolved)
          .toList();

      return VrchatStatus(
        description: description,
        indicator: indicator,
        serviceGroups: serviceGroups,
        activeIncidents: activeIncidents,
        lastUpdated: DateTime.now(),
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to fetch VRChat status',
        subCategory: 'vrchat_status',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  VrchatStatusIndicator _parseIndicator(String indicator) {
    switch (indicator) {
      case 'none':
        return VrchatStatusIndicator.none;
      case 'minor':
        return VrchatStatusIndicator.minor;
      case 'major':
        return VrchatStatusIndicator.major;
      case 'critical':
        return VrchatStatusIndicator.critical;
      default:
        return VrchatStatusIndicator.none;
    }
  }

  List<VrchatServiceGroup> _parseComponents(List components) {
    final groups = <String, Map<String, dynamic>>{};
    final servicesByGroup = <String, List<VrchatServiceStatus>>{};

    for (final component in components) {
      if (component['group'] == true) {
        final groupId = component['id'] as String;
        groups[groupId] = {
          'name': component['name'] as String,
          'status': component['status'] as String,
        };
      } else if (component['group'] == false) {
        final groupId = component['group_id'] as String?;
        if (groupId != null) {
          servicesByGroup.putIfAbsent(groupId, () => []);
          servicesByGroup[groupId]!.add(
            VrchatServiceStatus(
              name: component['name'] as String,
              status: component['status'] as String,
            ),
          );
        }
      }
    }

    final result = <VrchatServiceGroup>[];
    for (final entry in groups.entries) {
      final groupId = entry.key;
      final groupData = entry.value;
      final services = servicesByGroup[groupId] ?? [];

      result.add(
        VrchatServiceGroup(
          name: groupData['name'] as String,
          status: groupData['status'] as String,
          services: services,
        ),
      );
    }

    return result;
  }

  List<Incident> _parseIncidents(List incidents) {
    return incidents.map((incident) {
      final incidentData = incident as Map<String, dynamic>;
      return Incident(
        id: incidentData['id'] as String,
        name: incidentData['name'] as String,
        status: _parseIncidentStatus(incidentData['status']),
        impact: incidentData['impact'] as String? ?? '',
        updates: _parseUpdates(incidentData['incident_updates'] as List),
        createdAt: DateTime.parse(incidentData['created_at'] as String),
        resolvedAt: incidentData['resolved_at'] != null
            ? DateTime.parse(incidentData['resolved_at'] as String)
            : null,
      );
    }).toList();
  }

  IncidentStatus _parseIncidentStatus(String status) {
    switch (status) {
      case 'investigating':
        return IncidentStatus.investigating;
      case 'identified':
        return IncidentStatus.identified;
      case 'monitoring':
        return IncidentStatus.monitoring;
      case 'resolved':
        return IncidentStatus.resolved;
      default:
        return IncidentStatus.investigating;
    }
  }

  List<IncidentUpdate> _parseUpdates(List updates) {
    return updates.map((update) {
      final updateData = update as Map<String, dynamic>;
      return IncidentUpdate(
        status: _parseIncidentStatus(updateData['status']),
        body: updateData['body'] as String? ?? '',
        createdAt: DateTime.parse(updateData['created_at'] as String),
      );
    }).toList();
  }
}
