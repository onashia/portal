import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vrchat_status.dart';
import 'auth_provider.dart';
import 'app_version_provider.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../services/vrchat_status_service.dart';
import '../utils/timing_utils.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import 'portal_status_request_runner_provider.dart';
import 'polling_lifecycle.dart';
import 'refresh_cooldown_handler.dart';

@immutable
class VrchatStatusState {
  static const _unset = Object();

  final VrchatStatus? status;
  final bool isLoading;
  final String? errorMessage;

  const VrchatStatusState({
    this.status,
    required this.isLoading,
    this.errorMessage,
  });

  VrchatStatusState copyWith({
    VrchatStatus? status,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) {
    return VrchatStatusState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class VrchatStatusNotifier extends AsyncNotifier<VrchatStatusState> {
  final _statusLoop = RefreshLoopController();
  late final VrchatStatusService _service;
  bool _isRefreshing = false;

  @visibleForTesting
  bool get hasActiveRefreshTimer => _statusLoop.hasTimer;

  bool _isAuthenticated() =>
      ref.read(authSessionSnapshotProvider).isAuthenticated;

  bool _statusActive() => ref.mounted && _isAuthenticated();

  bool _canCommitRefreshResult() => _statusActive();

  @override
  VrchatStatusState build() {
    _service = VrchatStatusService(ref.read(dioProvider));

    ref.listen<AuthSessionSnapshot>(authSessionSnapshotProvider, (
      previous,
      next,
    ) {
      final wasAuthenticated = previous?.isAuthenticated == true;
      final isAuthenticated = next.isAuthenticated;

      if (!isAuthenticated) {
        _statusLoop.reset();
        final current = state.asData?.value;
        state = AsyncData(
          current?.copyWith(isLoading: true, errorMessage: null) ??
              const VrchatStatusState(isLoading: true),
        );
        return;
      }

      if (!wasAuthenticated && !_isRefreshing) {
        Future.microtask(() => _requestStatusRefresh(immediate: true));
        return;
      }

      Future.microtask(_reconcileStatusLoop);
    });

    if (_isAuthenticated()) {
      Future.microtask(() => _requestStatusRefresh(immediate: true));
    }

    ref.onDispose(_statusLoop.reset);

    return const VrchatStatusState(isLoading: true);
  }

  Duration _statusPollingDelay() {
    return TimingUtils.durationWithJitter(
      baseSeconds: AppConstants.vrchatStatusPollingIntervalSeconds,
      jitterSeconds: AppConstants.vrchatStatusPollingJitterSeconds,
    );
  }

  void _requestStatusRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    _statusLoop.requestRefresh(
      isActive: _statusActive(),
      isInFlight: _isRefreshing,
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
      reconcile: _reconcileStatusLoop,
      runNow: ({required bypassRateLimit}) {
        unawaited(refresh(bypassRateLimit: bypassRateLimit));
      },
      scheduleNextTick: () => _scheduleNextRefresh(),
    );
  }

  void _scheduleNextRefresh({Duration? overrideDelay}) {
    _statusLoop.scheduleNextTick(
      isActive: _statusActive,
      reconcile: _reconcileStatusLoop,
      resolveDelay: _statusPollingDelay,
      requestRefresh: () => _requestStatusRefresh(immediate: true),
      isMounted: () => ref.mounted,
      overrideDelay: overrideDelay,
    );
  }

  void _reconcileStatusLoop() {
    reconcileSingleLoopRefresh(
      loop: _statusLoop,
      isActive: _statusActive(),
      isInFlight: _isRefreshing,
      requestRefresh: () => _requestStatusRefresh(immediate: true),
      onInactive: _statusLoop.reset,
    );
  }

  /// Refreshes VRChat status.
  ///
  /// By default, refreshes are cooldown-aware. Manual actions should pass
  /// `bypassRateLimit: true` when an explicit user-triggered refresh should
  /// ignore active cooldown.
  Future<void> refresh({bool bypassRateLimit = false}) async {
    if (!_statusActive()) {
      _reconcileStatusLoop();
      return;
    }

    if (_isRefreshing) {
      _statusLoop.queuePending(bypassRateLimit: bypassRateLimit);
      return;
    }

    _statusLoop.cancelTimer();

    final runner = ref.read(portalStatusRequestRunnerProvider);
    if (RefreshCooldownHandler.shouldDeferForCooldown(
      cooldownTracker: runner,
      bypassRateLimit: bypassRateLimit,
      lane: ApiRequestLane.status,
      logContext: 'vrchat_status',
      fallbackDelay: _statusPollingDelay(),
      onDefer: (delay) => _scheduleNextRefresh(overrideDelay: delay),
    )) {
      return;
    }

    _isRefreshing = true;
    try {
      AppLogger.info('Refreshing VRChat status', subCategory: 'vrchat_status');
      final status = await runner.run<VrchatStatus>(
        lane: ApiRequestLane.status,
        request: (extra) => _service.fetchStatus(extra: extra),
      );
      if (!_canCommitRefreshResult()) {
        return;
      }
      state = AsyncData(VrchatStatusState(status: status, isLoading: false));
    } catch (e, s) {
      AppLogger.error(
        'VRChat status refresh failed',
        subCategory: 'vrchat_status',
        error: e,
        stackTrace: s,
      );
      if (!_canCommitRefreshResult()) {
        return;
      }
      state = AsyncData(
        VrchatStatusState(isLoading: false, errorMessage: e.toString()),
      );
    } finally {
      _isRefreshing = false;
      _afterRefresh();
    }
  }

  void _afterRefresh() {
    if (!ref.mounted || _isRefreshing) {
      return;
    }

    final active = _statusActive();
    drainSingleLoopRefreshOrScheduleNext(
      loop: _statusLoop,
      isMounted: ref.mounted,
      isInFlight: _isRefreshing,
      isActive: active,
      runNow: ({required bypassRateLimit}) {
        unawaited(refresh(bypassRateLimit: bypassRateLimit));
      },
      scheduleNextTick: () => _scheduleNextRefresh(),
      reconcile: _reconcileStatusLoop,
    );
  }
}

final dioProvider = Provider<Dio>((ref) {
  final appVersion = ref.read(appVersionProvider);
  final dio = Dio();
  // Configure User-Agent header as required by VRChat API
  dio.options.headers['User-Agent'] =
      'Portal/$appVersion (+https://github.com/onashia/portal)';
  // Add reasonable timeouts to prevent hanging on network issues
  dio.options.connectTimeout = const Duration(seconds: 10);
  dio.options.receiveTimeout = const Duration(seconds: 10);
  return dio;
});

final vrchatStatusProvider =
    AsyncNotifierProvider<VrchatStatusNotifier, VrchatStatusState>(
      VrchatStatusNotifier.new,
    );
