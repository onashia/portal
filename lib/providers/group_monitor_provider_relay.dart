// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'group_monitor_provider.dart';

extension GroupMonitorRelayExtension on GroupMonitorNotifier {
  void _bindRelayStreams() {
    _relayHintSubscription = _relayHintService.hints.listen(_handleRelayHint);
    _relayStatusSubscription = _relayHintService.statuses.listen((status) {
      if (!ref.mounted) {
        return;
      }
      final didConnectionChange = state.relayConnected != status.connected;
      final didErrorChange = state.lastRelayError != status.error;
      if (didConnectionChange || didErrorChange) {
        state = state.copyWith(
          relayConnected: status.connected,
          lastRelayError: status.error,
          relayTemporarilyDisabledUntil: _relayHintService.runtimeDisabledUntil,
        );
      }

      if (status.connected) {
        _relayFailureStreak = 0;
      } else if (status.error != null) {
        _recordRelayFailure(reason: status.error!);
      }
    });
  }

  String _createRelayClientId({required String userId}) {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return '$userId-$micros';
  }

  bool _shouldConnectRelay() {
    if (!ref.mounted) {
      return false;
    }

    if (!AppConstants.relayAssistEnabled || !state.relayAssistEnabled) {
      return false;
    }
    if (!_relayHintService.isConfigured) {
      return false;
    }
    if (state.relayTemporarilyDisabledUntil != null &&
        state.relayTemporarilyDisabledUntil!.isAfter(DateTime.now())) {
      return false;
    }
    if (!_canPollForCurrentSession()) {
      return false;
    }
    return state.isMonitoring &&
        state.autoInviteEnabled &&
        state.isBoostActive &&
        state.boostedGroupId != null;
  }

  void _reconcileRelayConnection() {
    if (!ref.mounted) {
      unawaited(_relayHintService.disconnect());
      return;
    }

    if (!_shouldConnectRelay()) {
      if (state.relayConnected || state.lastRelayError != null) {
        state = state.copyWith(
          relayConnected: false,
          lastRelayError: null,
          relayTemporarilyDisabledUntil: _relayHintService.runtimeDisabledUntil,
        );
      }
      unawaited(_relayHintService.disconnect());
      return;
    }

    final groupId = state.boostedGroupId;
    if (groupId == null) {
      return;
    }

    unawaited(
      _relayHintService.connect(
        groupId: groupId,
        userId: arg,
        clientId: _relayClientId,
      ),
    );
  }

  void _handleRelayHint(RelayHintMessage hint) {
    if (!ref.mounted) {
      return;
    }
    final now = DateTime.now();
    _pruneRelayDedupeState(now);

    if (!hint.isStructurallyValid || hint.isExpired(now: now)) {
      _recordRelayFailure(reason: 'invalid_or_expired_hint');
      return;
    }

    final boostedGroupId = state.boostedGroupId;
    if (!state.isMonitoring ||
        !state.autoInviteEnabled ||
        boostedGroupId == null ||
        boostedGroupId != hint.groupId) {
      return;
    }

    final hintDedupeKey = 'hint:${hint.hintId}';
    if (_relayHintDedupe.isBlocked(hintDedupeKey, now)) {
      return;
    }

    final instanceDedupeKey = 'instance:${hint.instanceKey}';
    if (_relayHintDedupe.isBlocked(instanceDedupeKey, now)) {
      return;
    }

    const hintTtl = Duration(seconds: AppConstants.relayHintDedupeSeconds);
    _relayHintDedupe.record(hintDedupeKey, now: now, ttl: hintTtl);
    _relayHintDedupe.record(instanceDedupeKey, now: now, ttl: hintTtl);

    state = state.copyWith(
      relayHintsReceived: state.relayHintsReceived + 1,
      lastRelayHintAt: now,
      lastRelayError: null,
    );

    final cancelToken = CancelToken();
    unawaited(_attemptInviteFromRelayHint(hint, cancelToken: cancelToken));
  }

  Future<void> _attemptInviteFromRelayHint(
    RelayHintMessage hint, {
    required CancelToken cancelToken,
  }) async {
    InviteRetryOutcome? outcome;
    _registerRelayInviteCancelToken(cancelToken);
    try {
      try {
        outcome = await _autoInviteService.attemptAutoInviteFromHint(
          hint: hint,
          enabled: state.autoInviteEnabled && state.isMonitoring,
          maxRetryWindow: const Duration(
            seconds: AppConstants.relayInviteRetryWindowSeconds,
          ),
          cancelToken: cancelToken,
        );
      } catch (e, s) {
        AppLogger.error(
          'Relay auto-invite from hint failed unexpectedly',
          subCategory: 'group_monitor',
          error: e,
          stackTrace: s,
        );
        _recordRelayFailure(reason: 'unexpected_invite_error');
        return;
      }
    } finally {
      _unregisterRelayInviteCancelToken(cancelToken);
    }

    if (outcome == null || !ref.mounted) {
      return;
    }

    switch (outcome) {
      case InviteRetryOutcome.sent:
        _relayFailureStreak = 0;
        return;
      case InviteRetryOutcome.cancelled:
        return;
      case InviteRetryOutcome.hardFailure:
        _recordRelayFailure(reason: 'hard_failure');
        return;
      case InviteRetryOutcome.transientFailureExhausted:
        _recordRelayFailure(reason: 'transient_exhausted');
        return;
      case InviteRetryOutcome.nonRetryableFailure:
        _recordRelayFailure(reason: 'non_retryable_failure');
        return;
    }
  }

  void _publishRelayHintForNewBoostedInstances({
    required String groupId,
    required List<GroupInstanceWithGroup> newInstances,
    required DateTime detectedAt,
  }) {
    if (!ref.mounted) {
      return;
    }
    if (!state.relayConnected || !state.relayAssistEnabled) {
      return;
    }
    if (state.boostedGroupId != groupId) {
      return;
    }

    GroupInstanceWithGroup? best;
    for (final candidate in newInstances) {
      if (!shouldAttemptSelfInviteForInstance(candidate.instance)) {
        continue;
      }
      if (best == null || candidate.instance.nUsers > best.instance.nUsers) {
        best = candidate;
      }
    }

    if (best == null) {
      return;
    }

    final now = DateTime.now();
    _pruneRelayDedupeState(now);
    final publishKey =
        '${best.groupId}|${best.instance.worldId}|${best.instance.instanceId}';
    if (_relayPublishDedupe.isBlocked(publishKey, now)) {
      return;
    }

    _relayPublishDedupe.record(
      publishKey,
      now: now,
      ttl: const Duration(seconds: AppConstants.relayPublishDedupeSeconds),
    );

    final hint = RelayHintMessage.create(
      groupId: groupId,
      worldId: best.instance.worldId,
      instanceId: best.instance.instanceId,
      nUsers: best.instance.nUsers,
      sourceClientId: _relayClientId,
      now: detectedAt,
    );

    unawaited(_relayHintService.publishHint(hint));
    state = state.copyWith(
      relayHintsPublished: state.relayHintsPublished + 1,
      lastRelayError: null,
    );
  }

  void _recordRelayFailure({required String reason}) {
    if (!ref.mounted) {
      return;
    }
    _relayFailureStreak += 1;
    state = state.copyWith(lastRelayError: reason);

    if (_relayFailureStreak < AppConstants.relayCircuitBreakerThreshold) {
      return;
    }

    final disabledUntil = DateTime.now().add(
      const Duration(seconds: AppConstants.relayCircuitBreakerCooldownSeconds),
    );
    state = state.copyWith(
      relayConnected: false,
      relayTemporarilyDisabledUntil: disabledUntil,
      lastRelayError: 'relay_circuit_breaker',
    );
    _relayFailureStreak = 0;
    unawaited(_relayHintService.disconnect());
    AppLogger.warning(
      'Relay circuit breaker opened until ${disabledUntil.toIso8601String()}',
      subCategory: 'relay',
    );
  }

  void _pruneRelayDedupeState(DateTime now) {
    _relayHintDedupe.prune(now);
    _relayPublishDedupe.prune(now);
  }
}
