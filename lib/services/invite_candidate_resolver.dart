import 'package:dio/dio.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/app_constants.dart';
import '../models/group_instance_with_group.dart';
import '../providers/group_instance_normalization.dart';
import '../providers/group_invite_and_boost.dart';
import '../providers/group_monitor_api.dart';
import 'api_rate_limit_coordinator.dart';
import '../utils/app_logger.dart';
import '../utils/dedupe_tracker.dart';

enum InviteCandidateVerificationState { verifiedEligible, unresolvedFallback }

enum _InviteCandidateVerificationOutcome {
  verifiedEligible,
  fullOrQueued,
  invalid,
  unresolvedFallback,
}

typedef _InviteCandidateVerificationResult = ({
  Instance? effectiveInstance,
  _InviteCandidateVerificationOutcome outcome,
});

enum _EnrichmentFailureClassification { invalid, unresolved }

typedef _EnrichmentLookupResult = ({
  Instance? instance,
  _EnrichmentFailureClassification? failureClassification,
});

class ResolvedInviteCandidate {
  const ResolvedInviteCandidate({
    required this.discoveryInstance,
    required this.effectiveInstance,
    required this.verificationState,
  });

  final Instance discoveryInstance;
  final Instance effectiveInstance;
  final InviteCandidateVerificationState verificationState;

  GroupInstanceWithGroup toGroupInstanceWithGroup(String groupId) {
    return GroupInstanceWithGroup(
      instance: effectiveInstance,
      groupId: groupId,
    );
  }
}

class InviteCandidateResolver {
  final Map<String, ({Instance instance, DateTime fetchedAt})>
  _enrichedInstanceByKey =
      <String, ({Instance instance, DateTime fetchedAt})>{};
  final Map<String, DateTime> _enrichmentFailureUntilByKey =
      <String, DateTime>{};
  final Map<String, _EnrichmentFailureClassification>
  _enrichmentFailureClassificationByKey =
      <String, _EnrichmentFailureClassification>{};
  final _enrichmentFailureLogDedupe = DedupeTracker();

  void pruneState(DateTime now, {Set<String> retainedKeys = const {}}) {
    _enrichmentFailureLogDedupe.prune(now);
    _enrichmentFailureUntilByKey.removeWhere((key, blockedUntil) {
      final shouldRemove = !blockedUntil.isAfter(now);
      if (shouldRemove) {
        _enrichmentFailureClassificationByKey.remove(key);
      }
      return shouldRemove;
    });
    _enrichedInstanceByKey.removeWhere(
      (_, cached) =>
          now.difference(cached.fetchedAt) >
          const Duration(
            seconds: AppConstants.groupInstanceEnrichmentTtlSeconds,
          ),
    );
    _enrichedInstanceByKey.removeWhere((key, _) => !retainedKeys.contains(key));
    _enrichmentFailureClassificationByKey.removeWhere(
      (key, _) =>
          !_enrichmentFailureUntilByKey.containsKey(key) &&
          !retainedKeys.contains(key),
    );
  }

  Instance? cachedEnrichedInstance({
    required String worldId,
    required String instanceId,
    required DateTime now,
  }) {
    final key = groupInstanceStableKey(
      worldId: worldId,
      instanceId: instanceId,
    );
    final cached = _enrichedInstanceByKey[key];
    if (cached == null) {
      return null;
    }

    final ttl = Duration(
      seconds: AppConstants.groupInstanceEnrichmentTtlSeconds,
    );
    if (now.difference(cached.fetchedAt) > ttl) {
      _enrichedInstanceByKey.remove(key);
      return null;
    }

    return cached.instance;
  }

  Future<List<Instance>> enrichHighestPopulationInstanceForDisplay({
    required GroupMonitorApi api,
    required List<Instance> discoveryInstances,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    void Function(ApiRequestLane lane)? onApiCall,
  }) async {
    if (discoveryInstances.isEmpty) {
      return discoveryInstances;
    }

    final best = _sortDiscoveryInstances(discoveryInstances).first;
    final result = await _loadEnrichedInstance(
      api: api,
      discoveryInstance: best,
      groupId: groupId,
      lane: lane,
      laneLabel: laneLabel,
      onApiCall: onApiCall,
      reasonPrefix: 'display enrichment',
    );
    final enriched = result.instance;
    if (enriched == null) {
      return discoveryInstances;
    }

    final nextInstances = discoveryInstances.toList(growable: false);
    final index = nextInstances.indexWhere(
      (candidate) =>
          candidate.worldId == best.worldId &&
          candidate.instanceId == best.instanceId,
    );
    if (index == -1) {
      return discoveryInstances;
    }

    nextInstances[index] = mergeDiscoveryInstanceWithEnrichment(
      discoveryInstance: nextInstances[index],
      enrichedInstance: enriched,
      groupId: groupId,
    );
    return nextInstances;
  }

  Future<ResolvedInviteCandidate?> resolveBestAutoInviteTarget({
    required GroupMonitorApi api,
    required List<Instance> discoveryInstances,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    int maxCandidatesToVerify =
        AppConstants.groupInstanceInviteVerificationMaxCandidates,
    void Function(ApiRequestLane lane)? onApiCall,
  }) async {
    if (discoveryInstances.isEmpty) {
      return null;
    }

    var verifiedCount = 0;
    for (final candidate in _sortDiscoveryInstances(discoveryInstances)) {
      if (!hasValidSelfInviteIdentifiers(candidate)) {
        AppLogger.warning(
          'Skipping auto-invite candidate with invalid identifiers for group '
          '$groupId (${candidate.worldId}:${candidate.instanceId}, '
          'users=${candidate.nUsers})',
          subCategory: 'group_monitor',
        );
        continue;
      }

      if (verifiedCount >= maxCandidatesToVerify) {
        if (isSelfInviteUnavailableForCapacity(candidate)) {
          final reason = candidate.hasCapacityForYou == false
              ? 'cached_no_capacity'
              : candidate.queueSize > 0
              ? 'cached_queue_active'
              : 'cached_capacity_unknown';
          AppLogger.info(
            'Skipping auto-invite candidate after verification cap because '
            'cached metadata marks it unavailable for group '
            '$groupId (${candidate.worldId}:${candidate.instanceId}, '
            'users=${candidate.nUsers}, hasCapacityForYou='
            '${candidate.hasCapacityForYou}, queueEnabled='
            '${candidate.queueEnabled}, queueSize=${candidate.queueSize}, '
            'reason=$reason)',
            subCategory: 'group_monitor',
          );
          continue;
        }
        AppLogger.debug(
          'Stopping auto-invite verification for $groupId after '
          '$verifiedCount candidates ($laneLabel)',
          subCategory: 'group_monitor',
        );
        return _buildFallbackCandidate(
          candidate: candidate,
          groupId: groupId,
          laneLabel: laneLabel,
          reason: 'verification_cap_reached',
        );
      }

      final verification = await _verifyAutoInviteCandidate(
        api: api,
        discoveryInstance: candidate,
        groupId: groupId,
        lane: lane,
        laneLabel: laneLabel,
        onApiCall: onApiCall,
      );
      switch (verification.outcome) {
        case _InviteCandidateVerificationOutcome.verifiedEligible:
          return ResolvedInviteCandidate(
            discoveryInstance: candidate,
            effectiveInstance: verification.effectiveInstance!,
            verificationState:
                InviteCandidateVerificationState.verifiedEligible,
          );
        case _InviteCandidateVerificationOutcome.fullOrQueued:
          verifiedCount += 1;
          continue;
        case _InviteCandidateVerificationOutcome.invalid:
          continue;
        case _InviteCandidateVerificationOutcome.unresolvedFallback:
          return _buildFallbackCandidate(
            candidate: candidate,
            groupId: groupId,
            laneLabel: laneLabel,
            reason: 'verification_unresolved',
          );
      }
    }

    return null;
  }

  List<Instance> _sortDiscoveryInstances(List<Instance> instances) {
    final sorted = instances.toList(growable: false)
      ..sort((a, b) {
        final byUsers = b.nUsers.compareTo(a.nUsers);
        if (byUsers != 0) {
          return byUsers;
        }
        return a.instanceId.compareTo(b.instanceId);
      });
    return sorted;
  }

  Future<_EnrichmentLookupResult> _loadEnrichedInstance({
    required GroupMonitorApi api,
    required Instance discoveryInstance,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    required String reasonPrefix,
    void Function(ApiRequestLane lane)? onApiCall,
  }) async {
    if (!hasValidSelfInviteIdentifiers(discoveryInstance)) {
      return (instance: null, failureClassification: null);
    }

    final now = DateTime.now();
    final key = groupInstanceStableKey(
      worldId: discoveryInstance.worldId,
      instanceId: discoveryInstance.instanceId,
    );
    final cachedEntry = _enrichedInstanceByKey[key];
    if (cachedEntry != null &&
        now.difference(cachedEntry.fetchedAt) >
            const Duration(
              seconds: AppConstants.groupInstanceEnrichmentTtlSeconds,
            )) {
      _enrichedInstanceByKey.remove(key);
      AppLogger.debug(
        'Re-enriching instance after cache expiry for $groupId '
        '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
        '($laneLabel)',
        subCategory: 'group_monitor',
      );
    }

    final cached = cachedEnrichedInstance(
      worldId: discoveryInstance.worldId,
      instanceId: discoveryInstance.instanceId,
      now: now,
    );
    if (cached != null) {
      AppLogger.debug(
        '$reasonPrefix cache hit for $groupId '
        '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
        '($laneLabel)',
        subCategory: 'group_monitor',
      );
      return (instance: cached, failureClassification: null);
    }

    final blockedUntil = _enrichmentFailureUntilByKey[key];
    if (blockedUntil != null && blockedUntil.isAfter(now)) {
      AppLogger.debug(
        'Skipping $reasonPrefix due to cooldown for $groupId '
        '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
        '($laneLabel)',
        subCategory: 'group_monitor',
      );
      return (
        instance: null,
        failureClassification: _enrichmentFailureClassificationByKey[key],
      );
    }

    AppLogger.debug(
      'Fetching instance enrichment for $groupId '
      '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
      '($laneLabel, reason=$reasonPrefix)',
      subCategory: 'group_monitor',
    );

    onApiCall?.call(lane);
    try {
      final response = await api
          .getInstance(
            worldId: discoveryInstance.worldId,
            instanceId: discoveryInstance.instanceId,
            lane: lane,
          )
          .timeout(
            const Duration(
              seconds: AppConstants.groupInstancesRequestTimeoutSeconds,
            ),
          );

      final enriched = response.data;
      if (enriched == null) {
        _recordEnrichmentFailure(
          key: key,
          groupId: groupId,
          instance: discoveryInstance,
          laneLabel: laneLabel,
          reason: 'empty_response',
          classification: _EnrichmentFailureClassification.invalid,
        );
        return (
          instance: null,
          failureClassification: _EnrichmentFailureClassification.invalid,
        );
      }

      _enrichedInstanceByKey[key] = (instance: enriched, fetchedAt: now);
      _enrichmentFailureUntilByKey.remove(key);
      _enrichmentFailureClassificationByKey.remove(key);
      AppLogger.info(
        'Instance enrichment succeeded for $groupId '
        '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
        '($laneLabel)',
        subCategory: 'group_monitor',
      );
      return (instance: enriched, failureClassification: null);
    } on DioException catch (e, s) {
      final statusCode = e.response?.statusCode;
      // VRChat instance-detail 404s are treated as invalid targets rather than
      // transient verification failures.
      final classification = statusCode == 404
          ? _EnrichmentFailureClassification.invalid
          : _EnrichmentFailureClassification.unresolved;
      _recordEnrichmentFailure(
        key: key,
        groupId: groupId,
        instance: discoveryInstance,
        laneLabel: laneLabel,
        reason: statusCode == 404
            ? 'invalid_not_found'
            : statusCode == null
            ? e.type.name
            : 'status_$statusCode',
        classification: classification,
        error: e,
        stackTrace: s,
      );
      return (instance: null, failureClassification: classification);
    } catch (e, s) {
      _recordEnrichmentFailure(
        key: key,
        groupId: groupId,
        instance: discoveryInstance,
        laneLabel: laneLabel,
        reason: 'unexpected',
        classification: _EnrichmentFailureClassification.unresolved,
        error: e,
        stackTrace: s,
      );
      return (
        instance: null,
        failureClassification: _EnrichmentFailureClassification.unresolved,
      );
    }
  }

  Future<_InviteCandidateVerificationResult> _verifyAutoInviteCandidate({
    required GroupMonitorApi api,
    required Instance discoveryInstance,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    void Function(ApiRequestLane lane)? onApiCall,
  }) async {
    final result = await _loadEnrichedInstance(
      api: api,
      discoveryInstance: discoveryInstance,
      groupId: groupId,
      lane: lane,
      laneLabel: laneLabel,
      onApiCall: onApiCall,
      reasonPrefix: 'auto-invite verification',
    );
    final enriched = result.instance;
    if (enriched == null) {
      return (
        effectiveInstance: null,
        outcome:
            result.failureClassification ==
                _EnrichmentFailureClassification.invalid
            ? _InviteCandidateVerificationOutcome.invalid
            : _InviteCandidateVerificationOutcome.unresolvedFallback,
      );
    }

    final effective = mergeDiscoveryInstanceWithEnrichment(
      discoveryInstance: discoveryInstance,
      enrichedInstance: enriched,
      groupId: groupId,
    );
    if (isSelfInviteUnavailableForCapacity(effective)) {
      final reason = effective.hasCapacityForYou == false
          ? 'no_capacity'
          : effective.queueSize > 0
          ? 'queue_active'
          : 'capacity_unknown';
      AppLogger.info(
        'Skipping verified unavailable auto-invite candidate for group '
        '$groupId (${effective.worldId}:${effective.instanceId}, '
        'users=${effective.nUsers}, hasCapacityForYou='
        '${effective.hasCapacityForYou}, queueEnabled=${effective.queueEnabled}, '
        'queueSize=${effective.queueSize}, reason=$reason)',
        subCategory: 'group_monitor',
      );
      return (
        effectiveInstance: effective,
        outcome: _InviteCandidateVerificationOutcome.fullOrQueued,
      );
    }

    if (effective.canRequestInvite == false) {
      AppLogger.info(
        'Using verified auto-invite candidate despite canRequestInvite=false '
        'for group $groupId (${effective.worldId}:${effective.instanceId}, '
        'users=${effective.nUsers})',
        subCategory: 'group_monitor',
      );
    }

    return (
      effectiveInstance: effective,
      outcome: _InviteCandidateVerificationOutcome.verifiedEligible,
    );
  }

  ResolvedInviteCandidate? _buildFallbackCandidate({
    required Instance? candidate,
    required String groupId,
    required String laneLabel,
    required String reason,
  }) {
    if (candidate == null) {
      return null;
    }
    AppLogger.info(
      'Using unresolved auto-invite fallback candidate for group '
      '$groupId (${candidate.worldId}:${candidate.instanceId}, '
      'users=${candidate.nUsers}, reason=$reason, lane=$laneLabel)',
      subCategory: 'group_monitor',
    );
    return ResolvedInviteCandidate(
      discoveryInstance: candidate,
      effectiveInstance: candidate,
      verificationState: InviteCandidateVerificationState.unresolvedFallback,
    );
  }

  void _recordEnrichmentFailure({
    required String key,
    required String groupId,
    required Instance instance,
    required String laneLabel,
    required String reason,
    required _EnrichmentFailureClassification classification,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final now = DateTime.now();
    _enrichmentFailureUntilByKey[key] = now.add(
      const Duration(
        seconds: AppConstants.groupInstanceEnrichmentFailureCooldownSeconds,
      ),
    );
    _enrichmentFailureClassificationByKey[key] = classification;

    final logKey = '$laneLabel|$key|$reason';
    final dedupeTtl = const Duration(
      seconds: AppConstants.groupInstanceEnrichmentLogDedupeSeconds,
    );
    if (_enrichmentFailureLogDedupe.isBlocked(logKey, now)) {
      return;
    }
    _enrichmentFailureLogDedupe.record(logKey, now: now, ttl: dedupeTtl);

    final message =
        'Instance enrichment failed for $groupId '
        '${instance.worldId}:${instance.instanceId} ($laneLabel, reason=$reason)';
    if (classification == _EnrichmentFailureClassification.invalid) {
      AppLogger.info(message, subCategory: 'group_monitor');
      return;
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final isTransient =
          statusCode == null ||
          statusCode == 409 ||
          statusCode == 429 ||
          statusCode >= 500;
      if (isTransient) {
        AppLogger.warning(message, subCategory: 'group_monitor');
        return;
      }
    }

    AppLogger.error(
      message,
      subCategory: 'group_monitor',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
