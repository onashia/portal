// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
// This part keeps relay behavior in a dedicated controller while still needing
// access to the notifier's Riverpod lifecycle and state setter within the same
// library.

part of 'group_monitor_provider.dart';

class _GroupMonitorRelayController {
  _GroupMonitorRelayController({required this.notifier, required this.service})
    : clientId = _createRelayClientId(userId: notifier.arg);

  final GroupMonitorNotifier notifier;
  final RelayHintService service;
  final String clientId;

  int _failureStreak = 0;
  final DedupeTracker _hintDedupe = DedupeTracker();
  final DedupeTracker _publishDedupe = DedupeTracker();
  final Set<CancelToken> _inviteCancelTokens = <CancelToken>{};
  StreamSubscription<RelayHintMessage>? _hintSubscription;
  StreamSubscription<RelayConnectionStatus>? _statusSubscription;

  bool get isConfigured => service.isConfigured;

  void bindStreams() {
    _hintSubscription = service.hints.listen(handleHint);
    _statusSubscription = service.statuses.listen((status) {
      if (!notifier.ref.mounted) {
        return;
      }
      final didConnectionChange =
          notifier.state.relayConnected != status.connected;
      final didErrorChange = notifier.state.lastRelayError != status.error;
      if (didConnectionChange || didErrorChange) {
        notifier.state = notifier.state.copyWith(
          relayConnected: status.connected,
          lastRelayError: status.error,
          relayTemporarilyDisabledUntil: service.runtimeDisabledUntil,
        );
      }

      if (status.connected) {
        _failureStreak = 0;
        if (notifier.state.relayTemporarilyDisabledUntil != null) {
          notifier.state = notifier.state.copyWith(
            relayTemporarilyDisabledUntil: null,
          );
        }
      } else if (status.error != null) {
        recordFailure(reason: status.error!);
      }
    });
  }

  Future<void> dispose() async {
    _cancelAllInviteTokens();
    await _hintSubscription?.cancel();
    _hintSubscription = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    await service.disconnect();
  }

  bool shouldConnect() {
    if (!notifier.ref.mounted) {
      return false;
    }

    if (!AppConstants.relayAssistEnabled ||
        !notifier.state.relayAssistEnabled) {
      return false;
    }
    if (!service.isConfigured) {
      return false;
    }
    if (notifier.state.relayTemporarilyDisabledUntil != null &&
        notifier.state.relayTemporarilyDisabledUntil!.isAfter(DateTime.now())) {
      return false;
    }
    if (!notifier._canPollForCurrentSession()) {
      return false;
    }
    return notifier.state.isMonitoring &&
        notifier.state.autoInviteEnabled &&
        notifier.state.isBoostActive &&
        notifier.state.boostedGroupId != null;
  }

  void reconcileConnection() {
    if (!notifier.ref.mounted) {
      unawaited(service.disconnect());
      return;
    }

    if (!shouldConnect()) {
      if (notifier.state.relayConnected ||
          notifier.state.lastRelayError != null) {
        notifier.state = notifier.state.copyWith(
          relayConnected: false,
          lastRelayError: null,
          relayTemporarilyDisabledUntil: service.runtimeDisabledUntil,
        );
      }
      unawaited(service.disconnect());
      return;
    }

    final groupId = notifier.state.boostedGroupId;
    if (groupId == null) {
      return;
    }

    unawaited(service.connect(groupId: groupId, clientId: clientId));
  }

  void handleHint(RelayHintMessage hint) {
    if (!notifier.ref.mounted) {
      return;
    }
    final now = DateTime.now();
    _pruneDedupeState(now);

    if (!hint.isStructurallyValid || hint.isExpired(now: now)) {
      recordFailure(reason: 'invalid_or_expired_hint');
      return;
    }

    final boostedGroupId = notifier.state.boostedGroupId;
    if (!notifier.state.isMonitoring ||
        !notifier.state.autoInviteEnabled ||
        boostedGroupId == null ||
        boostedGroupId != hint.groupId) {
      return;
    }

    final hintDedupeKey = 'hint:${hint.hintId}';
    if (_hintDedupe.isBlocked(hintDedupeKey, now)) {
      return;
    }

    final instanceDedupeKey = 'instance:${hint.instanceKey}';
    if (_hintDedupe.isBlocked(instanceDedupeKey, now)) {
      return;
    }

    const hintTtl = Duration(seconds: AppConstants.relayHintDedupeSeconds);
    _hintDedupe.record(hintDedupeKey, now: now, ttl: hintTtl);
    _hintDedupe.record(instanceDedupeKey, now: now, ttl: hintTtl);

    notifier.state = notifier.state.copyWith(
      relayHintsReceived: notifier.state.relayHintsReceived + 1,
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
    _inviteCancelTokens.add(cancelToken);
    try {
      try {
        outcome = await notifier._autoInviteService.attemptAutoInviteFromHint(
          hint: hint,
          enabled:
              notifier.state.autoInviteEnabled && notifier.state.isMonitoring,
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
        recordFailure(reason: 'unexpected_invite_error');
        return;
      }
    } finally {
      _inviteCancelTokens.remove(cancelToken);
    }

    if (outcome == null || !notifier.ref.mounted) {
      return;
    }

    switch (outcome) {
      case InviteRetryOutcome.sent:
        _failureStreak = 0;
        return;
      case InviteRetryOutcome.cancelled:
        return;
      case InviteRetryOutcome.hardFailure:
        recordFailure(reason: 'hard_failure');
        return;
      case InviteRetryOutcome.transientFailureExhausted:
        recordFailure(reason: 'transient_exhausted');
        return;
      case InviteRetryOutcome.nonRetryableFailure:
        recordFailure(reason: 'non_retryable_failure');
        return;
    }
  }

  void publishHintForNewBoostedInstances({
    required String groupId,
    required List<GroupInstanceWithGroup> newInstances,
    required DateTime detectedAt,
  }) {
    if (!notifier.ref.mounted) {
      return;
    }
    if (!notifier.state.relayConnected || !notifier.state.relayAssistEnabled) {
      return;
    }
    if (notifier.state.boostedGroupId != groupId) {
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
    _pruneDedupeState(now);
    final publishKey =
        '${best.groupId}|${best.instance.worldId}|${best.instance.instanceId}';
    if (_publishDedupe.isBlocked(publishKey, now)) {
      return;
    }

    _publishDedupe.record(
      publishKey,
      now: now,
      ttl: const Duration(seconds: AppConstants.relayPublishDedupeSeconds),
    );

    final hint = RelayHintMessage.create(
      groupId: groupId,
      worldId: best.instance.worldId,
      instanceId: best.instance.instanceId,
      nUsers: best.instance.nUsers,
      sourceClientId: clientId,
      now: detectedAt,
    );

    unawaited(service.publishHint(hint));
    notifier.state = notifier.state.copyWith(
      relayHintsPublished: notifier.state.relayHintsPublished + 1,
      lastRelayError: null,
    );
  }

  void recordFailure({required String reason}) {
    if (!notifier.ref.mounted) {
      return;
    }
    _failureStreak += 1;
    notifier.state = notifier.state.copyWith(lastRelayError: reason);

    if (_failureStreak < AppConstants.relayCircuitBreakerThreshold) {
      return;
    }

    final disabledUntil = DateTime.now().add(
      const Duration(seconds: AppConstants.relayCircuitBreakerCooldownSeconds),
    );
    notifier.state = notifier.state.copyWith(
      relayConnected: false,
      relayTemporarilyDisabledUntil: disabledUntil,
      lastRelayError: 'relay_circuit_breaker',
    );
    _failureStreak = 0;
    unawaited(service.disconnect());
    AppLogger.warning(
      'Relay circuit breaker opened until ${disabledUntil.toIso8601String()}',
      subCategory: 'relay',
    );
  }

  void _pruneDedupeState(DateTime now) {
    _hintDedupe.prune(now);
    _publishDedupe.prune(now);
  }

  void _cancelAllInviteTokens() {
    if (_inviteCancelTokens.isEmpty) {
      return;
    }

    final tokens = _inviteCancelTokens.toList(growable: false);
    _inviteCancelTokens.clear();
    for (final token in tokens) {
      if (!token.isCancelled) {
        token.cancel('group_monitor_disposed');
      }
    }
  }

  static String _createRelayClientId({required String userId}) {
    final rng = math.Random.secure();
    final bytes = List<int>.generate(8, (_) => rng.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$userId-$hex';
  }
}

extension GroupMonitorRelayExtension on GroupMonitorNotifier {
  void _bindRelayStreams() => _relayController.bindStreams();

  void _reconcileRelayConnection() => _relayController.reconcileConnection();

  void _publishRelayHintForNewBoostedInstances({
    required String groupId,
    required List<GroupInstanceWithGroup> newInstances,
    required DateTime detectedAt,
  }) {
    _relayController.publishHintForNewBoostedInstances(
      groupId: groupId,
      newInstances: newInstances,
      detectedAt: detectedAt,
    );
  }
}
