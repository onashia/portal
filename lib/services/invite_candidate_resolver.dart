import 'package:dio/dio.dart';
import 'package:vrchat_dart/vrchat_dart.dart' hide Response;

import '../constants/app_constants.dart';
import '../models/group_instance_with_group.dart';
import '../providers/group_instance_normalization.dart';
import '../providers/group_invite_and_boost.dart';
import '../utils/app_logger.dart';
import '../utils/dedupe_tracker.dart';
import 'api_rate_limit_coordinator.dart';

typedef InviteCandidateResolverFetchInstance =
    Future<Response<Instance>> Function({
      required String worldId,
      required String instanceId,
      required ApiRequestLane lane,
    });

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

typedef _EnrichmentState = ({
  Instance? instance,
  DateTime? fetchedAt,
  DateTime? blockedUntil,
  _EnrichmentFailureClassification? failureClassification,
});

class InviteCandidateResolver {
  InviteCandidateResolver({
    required InviteCandidateResolverFetchInstance fetchInstance,
  }) : _enrichmentCache = _InstanceEnrichmentCache(
         fetchInstance: fetchInstance,
       ),
       _selector = _InviteTargetSelector();

  final _InstanceEnrichmentCache _enrichmentCache;
  final _InviteTargetSelector _selector;

  void pruneState(DateTime now, {Set<String> retainedKeys = const {}}) {
    _enrichmentCache.pruneState(now, retainedKeys: retainedKeys);
  }

  Future<List<Instance>> normalizeAndEnrichFetchedGroupInstances({
    required List<GroupInstance> groupInstances,
    required String groupId,
    required Set<String> retainedKeys,
    required ApiRequestLane lane,
    required String laneLabel,
  }) async {
    final now = DateTime.now();
    _enrichmentCache.pruneState(now, retainedKeys: retainedKeys);

    final discoveryInstances = groupInstances
        .map(
          (groupInstance) => normalizeGroupInstance(
            groupInstance: groupInstance,
            groupId: groupId,
            enrichedInstance: _enrichmentCache.cachedEnrichedInstance(
              worldId: groupInstance.world.id,
              instanceId: groupInstance.instanceId,
              now: now,
            ),
          ),
        )
        .toList(growable: false);
    if (discoveryInstances.isEmpty) {
      return discoveryInstances;
    }

    final best = _sortDiscoveryInstances(discoveryInstances).first;
    final result = await _enrichmentCache.loadEnrichedInstance(
      discoveryInstance: best,
      groupId: groupId,
      lane: lane,
      laneLabel: laneLabel,
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

  Future<GroupInstanceWithGroup?> resolveBestAutoInviteTarget({
    required List<Instance> discoveryInstances,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    int maxCandidatesToVerify =
        AppConstants.groupInstanceInviteVerificationMaxCandidates,
  }) {
    return _selector.resolveBestAutoInviteTarget(
      discoveryInstances: discoveryInstances,
      groupId: groupId,
      lane: lane,
      laneLabel: laneLabel,
      enrichmentCache: _enrichmentCache,
      maxCandidatesToVerify: maxCandidatesToVerify,
    );
  }
}

class _InviteTargetSelector {
  Future<GroupInstanceWithGroup?> resolveBestAutoInviteTarget({
    required List<Instance> discoveryInstances,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    required _InstanceEnrichmentCache enrichmentCache,
    required int maxCandidatesToVerify,
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
        return _buildResolvedCandidate(
          instance: candidate,
          groupId: groupId,
          laneLabel: laneLabel,
          reason: 'verification_cap_reached',
        );
      }

      final verification = await _verifyAutoInviteCandidate(
        discoveryInstance: candidate,
        groupId: groupId,
        lane: lane,
        laneLabel: laneLabel,
        enrichmentCache: enrichmentCache,
      );
      switch (verification.outcome) {
        case _InviteCandidateVerificationOutcome.verifiedEligible:
          return GroupInstanceWithGroup(
            instance: verification.effectiveInstance!,
            groupId: groupId,
          );
        case _InviteCandidateVerificationOutcome.fullOrQueued:
          verifiedCount += 1;
          continue;
        case _InviteCandidateVerificationOutcome.invalid:
          continue;
        case _InviteCandidateVerificationOutcome.unresolvedFallback:
          return _buildResolvedCandidate(
            instance: candidate,
            groupId: groupId,
            laneLabel: laneLabel,
            reason: 'verification_unresolved',
          );
      }
    }

    return null;
  }

  Future<_InviteCandidateVerificationResult> _verifyAutoInviteCandidate({
    required Instance discoveryInstance,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    required _InstanceEnrichmentCache enrichmentCache,
  }) async {
    final result = await enrichmentCache.loadEnrichedInstance(
      discoveryInstance: discoveryInstance,
      groupId: groupId,
      lane: lane,
      laneLabel: laneLabel,
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

  GroupInstanceWithGroup _buildResolvedCandidate({
    required Instance instance,
    required String groupId,
    required String laneLabel,
    required String reason,
  }) {
    AppLogger.info(
      'Using unresolved auto-invite fallback candidate for group '
      '$groupId (${instance.worldId}:${instance.instanceId}, '
      'users=${instance.nUsers}, reason=$reason, lane=$laneLabel)',
      subCategory: 'group_monitor',
    );
    return GroupInstanceWithGroup(instance: instance, groupId: groupId);
  }
}

class _InstanceEnrichmentCache {
  _InstanceEnrichmentCache({
    required InviteCandidateResolverFetchInstance fetchInstance,
  }) : _fetchInstance = fetchInstance;

  final InviteCandidateResolverFetchInstance _fetchInstance;
  final Map<String, _EnrichmentState> _enrichmentStateByKey =
      <String, _EnrichmentState>{};
  final _enrichmentFailureLogDedupe = DedupeTracker();

  void pruneState(DateTime now, {Set<String> retainedKeys = const {}}) {
    _enrichmentFailureLogDedupe.prune(now);
    for (final key in _enrichmentStateByKey.keys.toList(growable: false)) {
      final state = _normalizedStateForKey(key, now);
      if (state == null) {
        _enrichmentStateByKey.remove(key);
        continue;
      }
      if (state.blockedUntil != null) {
        continue;
      }
      if (!retainedKeys.contains(key)) {
        _enrichmentStateByKey.remove(key);
      }
    }
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
    return _normalizedStateForKey(key, now)?.instance;
  }

  Future<_EnrichmentLookupResult> loadEnrichedInstance({
    required Instance discoveryInstance,
    required String groupId,
    required ApiRequestLane lane,
    required String laneLabel,
    required String reasonPrefix,
  }) async {
    if (!hasValidSelfInviteIdentifiers(discoveryInstance)) {
      return (instance: null, failureClassification: null);
    }

    final now = DateTime.now();
    final key = groupInstanceStableKey(
      worldId: discoveryInstance.worldId,
      instanceId: discoveryInstance.instanceId,
    );
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

    final state = _normalizedStateForKey(key, now);
    if (state?.blockedUntil?.isAfter(now) ?? false) {
      AppLogger.debug(
        'Skipping $reasonPrefix due to cooldown for $groupId '
        '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
        '($laneLabel)',
        subCategory: 'group_monitor',
      );
      return (
        instance: null,
        failureClassification: state!.failureClassification,
      );
    }

    AppLogger.debug(
      'Fetching instance enrichment for $groupId '
      '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
      '($laneLabel, reason=$reasonPrefix)',
      subCategory: 'group_monitor',
    );

    try {
      final response =
          await _fetchInstance(
            worldId: discoveryInstance.worldId,
            instanceId: discoveryInstance.instanceId,
            lane: lane,
          ).timeout(
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

      _enrichmentStateByKey[key] = (
        instance: enriched,
        fetchedAt: now,
        blockedUntil: null,
        failureClassification: null,
      );
      AppLogger.info(
        'Instance enrichment succeeded for $groupId '
        '${discoveryInstance.worldId}:${discoveryInstance.instanceId} '
        '($laneLabel)',
        subCategory: 'group_monitor',
      );
      return (instance: enriched, failureClassification: null);
    } on DioException catch (e, s) {
      final statusCode = e.response?.statusCode;
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

  _EnrichmentState? _normalizedStateForKey(String key, DateTime now) {
    final state = _enrichmentStateByKey[key];
    if (state == null) {
      return null;
    }

    final hasFreshInstance =
        state.instance != null &&
        state.fetchedAt != null &&
        now.difference(state.fetchedAt!) <=
            const Duration(
              seconds: AppConstants.groupInstanceEnrichmentTtlSeconds,
            );
    final isBlocked = state.blockedUntil?.isAfter(now) ?? false;

    if (!hasFreshInstance && !isBlocked) {
      _enrichmentStateByKey.remove(key);
      return null;
    }

    final normalized = (
      instance: hasFreshInstance ? state.instance : null,
      fetchedAt: hasFreshInstance ? state.fetchedAt : null,
      blockedUntil: isBlocked ? state.blockedUntil : null,
      failureClassification: isBlocked ? state.failureClassification : null,
    );
    _enrichmentStateByKey[key] = normalized;
    return normalized;
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
    _enrichmentStateByKey[key] = (
      instance: null,
      fetchedAt: null,
      blockedUntil: now.add(
        const Duration(
          seconds: AppConstants.groupInstanceEnrichmentFailureCooldownSeconds,
        ),
      ),
      failureClassification: classification,
    );

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
