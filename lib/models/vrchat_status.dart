import 'package:flutter/foundation.dart';

enum VrchatStatusIndicator { none, minor, major, critical }

enum IncidentStatus { investigating, identified, monitoring, resolved }

@immutable
class VrchatServiceStatus {
  final String name;
  final String status;

  const VrchatServiceStatus({required this.name, required this.status});

  VrchatServiceStatus copyWith({String? name, String? status}) {
    return VrchatServiceStatus(
      name: name ?? this.name,
      status: status ?? this.status,
    );
  }
}

@immutable
class VrchatServiceGroup {
  final String name;
  final String status;
  final List<VrchatServiceStatus> services;

  const VrchatServiceGroup({
    required this.name,
    required this.status,
    required this.services,
  });

  VrchatServiceGroup copyWith({
    String? name,
    String? status,
    List<VrchatServiceStatus>? services,
  }) {
    return VrchatServiceGroup(
      name: name ?? this.name,
      status: status ?? this.status,
      services: services ?? this.services,
    );
  }
}

@immutable
class VrchatStatus {
  final String description;
  final VrchatStatusIndicator indicator;
  final List<VrchatServiceGroup> serviceGroups;
  final List<Incident> activeIncidents;
  final DateTime lastUpdated;

  const VrchatStatus({
    required this.description,
    required this.indicator,
    required this.serviceGroups,
    required this.activeIncidents,
    required this.lastUpdated,
  });

  VrchatStatus copyWith({
    String? description,
    VrchatStatusIndicator? indicator,
    List<VrchatServiceGroup>? serviceGroups,
    List<Incident>? activeIncidents,
    DateTime? lastUpdated,
  }) {
    return VrchatStatus(
      description: description ?? this.description,
      indicator: indicator ?? this.indicator,
      serviceGroups: serviceGroups ?? this.serviceGroups,
      activeIncidents: activeIncidents ?? this.activeIncidents,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

@immutable
class Incident {
  final String id;
  final String name;
  final IncidentStatus status;
  final String impact;
  final List<IncidentUpdate> updates;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const Incident({
    required this.id,
    required this.name,
    required this.status,
    required this.impact,
    required this.updates,
    required this.createdAt,
    this.resolvedAt,
  });

  Incident copyWith({
    String? id,
    String? name,
    IncidentStatus? status,
    String? impact,
    List<IncidentUpdate>? updates,
    DateTime? createdAt,
    DateTime? resolvedAt,
  }) {
    return Incident(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      impact: impact ?? this.impact,
      updates: updates ?? this.updates,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }
}

@immutable
class IncidentUpdate {
  final IncidentStatus status;
  final String body;
  final DateTime createdAt;

  const IncidentUpdate({
    required this.status,
    required this.body,
    required this.createdAt,
  });

  IncidentUpdate copyWith({
    IncidentStatus? status,
    String? body,
    DateTime? createdAt,
  }) {
    return IncidentUpdate(
      status: status ?? this.status,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
