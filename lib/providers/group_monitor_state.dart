import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_instance_with_group.dart';

@immutable
class GroupMonitorState {
  static const _unset = Object();

  final List<LimitedUserGroups> allGroups;
  final Set<String> selectedGroupIds;
  final Map<String, List<GroupInstanceWithGroup>> groupInstances;
  final List<GroupInstanceWithGroup> newInstances;
  final String? newestInstanceId;
  final bool autoInviteEnabled;
  final String? boostedGroupId;
  final DateTime? boostExpiresAt;
  final int boostPollCount;
  final int? lastBoostLatencyMs;
  final DateTime? lastBoostFetchedAt;
  final Duration? boostFirstSeenAfter;
  final bool isMonitoring;
  final bool isLoading;
  final String? errorMessage;
  final Map<String, String> groupErrors;
  final DateTime? lastGroupsFetchTime;

  const GroupMonitorState({
    this.allGroups = const [],
    this.selectedGroupIds = const {},
    this.groupInstances = const {},
    this.newInstances = const [],
    this.newestInstanceId,
    this.autoInviteEnabled = true,
    this.boostedGroupId,
    this.boostExpiresAt,
    this.boostPollCount = 0,
    this.lastBoostLatencyMs,
    this.lastBoostFetchedAt,
    this.boostFirstSeenAfter,
    this.isMonitoring = false,
    this.isLoading = false,
    this.errorMessage,
    this.groupErrors = const {},
    this.lastGroupsFetchTime,
  });

  GroupMonitorState copyWith({
    List<LimitedUserGroups>? allGroups,
    Set<String>? selectedGroupIds,
    Map<String, List<GroupInstanceWithGroup>>? groupInstances,
    List<GroupInstanceWithGroup>? newInstances,
    String? newestInstanceId,
    bool? autoInviteEnabled,
    Object? boostedGroupId = _unset,
    Object? boostExpiresAt = _unset,
    int? boostPollCount,
    Object? lastBoostLatencyMs = _unset,
    Object? lastBoostFetchedAt = _unset,
    Object? boostFirstSeenAfter = _unset,
    bool? isMonitoring,
    bool? isLoading,
    Object? errorMessage = _unset,
    Map<String, String>? groupErrors,
    Object? lastGroupsFetchTime = _unset,
  }) {
    return GroupMonitorState(
      allGroups: allGroups ?? this.allGroups,
      selectedGroupIds: selectedGroupIds ?? this.selectedGroupIds,
      groupInstances: groupInstances ?? this.groupInstances,
      newInstances: newInstances ?? this.newInstances,
      newestInstanceId: newestInstanceId ?? this.newestInstanceId,
      autoInviteEnabled: autoInviteEnabled ?? this.autoInviteEnabled,
      boostedGroupId: boostedGroupId == _unset
          ? this.boostedGroupId
          : boostedGroupId as String?,
      boostExpiresAt: boostExpiresAt == _unset
          ? this.boostExpiresAt
          : boostExpiresAt as DateTime?,
      boostPollCount: boostPollCount ?? this.boostPollCount,
      lastBoostLatencyMs: lastBoostLatencyMs == _unset
          ? this.lastBoostLatencyMs
          : lastBoostLatencyMs as int?,
      lastBoostFetchedAt: lastBoostFetchedAt == _unset
          ? this.lastBoostFetchedAt
          : lastBoostFetchedAt as DateTime?,
      boostFirstSeenAfter: boostFirstSeenAfter == _unset
          ? this.boostFirstSeenAfter
          : boostFirstSeenAfter as Duration?,
      isMonitoring: isMonitoring ?? this.isMonitoring,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      groupErrors: groupErrors ?? this.groupErrors,
      lastGroupsFetchTime: lastGroupsFetchTime == _unset
          ? this.lastGroupsFetchTime
          : lastGroupsFetchTime as DateTime?,
    );
  }

  List<GroupInstanceWithGroup> get allInstancesSorted =>
      groupInstances.values.expand((instances) => instances).toList()
        ..sort((a, b) {
          final aTime = a.firstDetectedAt ?? DateTime.now();
          final bTime = b.firstDetectedAt ?? DateTime.now();
          return bTime.compareTo(aTime);
        });

  bool get isBoostActive =>
      boostedGroupId != null &&
      boostExpiresAt != null &&
      boostExpiresAt!.isAfter(DateTime.now());
}
