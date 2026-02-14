import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_instance_with_group.dart';

@immutable
class GroupMonitorState {
  static const _unset = Object();

  final List<LimitedUserGroups> allGroups;
  final Set<String> selectedGroupIds;
  final Map<String, List<GroupInstanceWithGroup>> groupInstances;
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
  final DateTime? lastBaselineAttemptAt;
  final DateTime? lastBaselineSuccessAt;
  final int? lastBaselinePolledGroupCount;
  final int? lastBaselineTotalInstances;
  final String? lastBaselineSkipReason;
  final DateTime? lastGroupsFetchTime;

  const GroupMonitorState({
    this.allGroups = const [],
    this.selectedGroupIds = const {},
    this.groupInstances = const {},
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
    this.lastBaselineAttemptAt,
    this.lastBaselineSuccessAt,
    this.lastBaselinePolledGroupCount,
    this.lastBaselineTotalInstances,
    this.lastBaselineSkipReason,
    this.lastGroupsFetchTime,
  });

  GroupMonitorState copyWith({
    List<LimitedUserGroups>? allGroups,
    Set<String>? selectedGroupIds,
    Map<String, List<GroupInstanceWithGroup>>? groupInstances,
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
    Object? lastBaselineAttemptAt = _unset,
    Object? lastBaselineSuccessAt = _unset,
    Object? lastBaselinePolledGroupCount = _unset,
    Object? lastBaselineTotalInstances = _unset,
    Object? lastBaselineSkipReason = _unset,
    Object? lastGroupsFetchTime = _unset,
  }) {
    return GroupMonitorState(
      allGroups: allGroups ?? this.allGroups,
      selectedGroupIds: selectedGroupIds ?? this.selectedGroupIds,
      groupInstances: groupInstances ?? this.groupInstances,
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
      lastBaselineAttemptAt: lastBaselineAttemptAt == _unset
          ? this.lastBaselineAttemptAt
          : lastBaselineAttemptAt as DateTime?,
      lastBaselineSuccessAt: lastBaselineSuccessAt == _unset
          ? this.lastBaselineSuccessAt
          : lastBaselineSuccessAt as DateTime?,
      lastBaselinePolledGroupCount: lastBaselinePolledGroupCount == _unset
          ? this.lastBaselinePolledGroupCount
          : lastBaselinePolledGroupCount as int?,
      lastBaselineTotalInstances: lastBaselineTotalInstances == _unset
          ? this.lastBaselineTotalInstances
          : lastBaselineTotalInstances as int?,
      lastBaselineSkipReason: lastBaselineSkipReason == _unset
          ? this.lastBaselineSkipReason
          : lastBaselineSkipReason as String?,
      lastGroupsFetchTime: lastGroupsFetchTime == _unset
          ? this.lastGroupsFetchTime
          : lastGroupsFetchTime as DateTime?,
    );
  }

  bool get isBoostActive =>
      boostedGroupId != null &&
      boostExpiresAt != null &&
      boostExpiresAt!.isAfter(DateTime.now());
}
