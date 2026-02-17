import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vrchat_status.dart';
import 'api_call_counter.dart';
import 'api_rate_limit_provider.dart';
import 'auth_provider.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../services/vrchat_status_service.dart';
import '../utils/timing_utils.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import 'polling_lifecycle.dart';

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
  Timer? _refreshTimer;
  late final VrchatStatusService _service;
  bool _isRefreshing = false;

  @visibleForTesting
  bool get hasActiveRefreshTimer => _refreshTimer != null;

  bool _isAuthenticated() =>
      ref.read(authSessionSnapshotProvider).isAuthenticated;

  bool _canCommitRefreshResult() => ref.mounted && _isAuthenticated();

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
        _disposeTimer();
        final current = state.asData?.value;
        state = AsyncData(
          current?.copyWith(isLoading: true, errorMessage: null) ??
              const VrchatStatusState(isLoading: true),
        );
        return;
      }

      if (!wasAuthenticated && !_isRefreshing) {
        Future.microtask(() => refresh(bypassRateLimit: false));
      }
    });

    if (_isAuthenticated()) {
      Future.microtask(() => refresh(bypassRateLimit: false));
    }

    ref.onDispose(_disposeTimer);

    return const VrchatStatusState(isLoading: true);
  }

  void _scheduleNextRefresh({Duration? overrideDelay}) {
    _refreshTimer?.cancel();

    final delay =
        overrideDelay ??
        TimingUtils.durationWithJitter(
          baseSeconds: AppConstants.vrchatStatusPollingIntervalSeconds,
          jitterSeconds: AppConstants.vrchatStatusPollingJitterSeconds,
        );

    _refreshTimer = Timer(delay, () async {
      if (!ref.mounted) {
        return;
      }
      if (!_isAuthenticated()) {
        _disposeTimer();
        return;
      }
      unawaited(refresh(bypassRateLimit: false));
    });
  }

  /// Refreshes VRChat status.
  ///
  /// By default, refreshes are cooldown-aware. Manual actions should pass
  /// `bypassRateLimit: true` when an explicit user-triggered refresh should
  /// ignore active cooldown.
  Future<void> refresh({bool bypassRateLimit = false}) async {
    if (!_isAuthenticated()) {
      _disposeTimer();
      return;
    }

    if (_isRefreshing) {
      return;
    }

    if (!bypassRateLimit) {
      final coordinator = ref.read(apiRateLimitCoordinatorProvider);
      final remaining = coordinator.remainingCooldown(ApiRequestLane.status);
      if (remaining != null) {
        AppLogger.debug(
          'Status refresh deferred due to cooldown'
          ' (${remaining.inSeconds}s remaining)',
          subCategory: 'vrchat_status',
        );
        ref
            .read(apiCallCounterProvider.notifier)
            .incrementThrottledSkip(lane: ApiRequestLane.status);
        _scheduleNextRefresh(
          overrideDelay: resolveCooldownAwareDelay(
            remainingCooldown: remaining,
            fallbackDelay: TimingUtils.durationWithJitter(
              baseSeconds: AppConstants.vrchatStatusPollingIntervalSeconds,
              jitterSeconds: AppConstants.vrchatStatusPollingJitterSeconds,
            ),
          ),
        );
        return;
      }
    }

    _isRefreshing = true;
    try {
      AppLogger.info('Refreshing VRChat status', subCategory: 'vrchat_status');
      ref
          .read(apiCallCounterProvider.notifier)
          .incrementApiCall(lane: ApiRequestLane.status);
      final status = await _service.fetchStatus(
        extra: apiRequestLaneExtra(ApiRequestLane.status),
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
      if (_canCommitRefreshResult()) {
        _scheduleNextRefresh();
      }
    }
  }

  void _disposeTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}

final dioProvider = Provider<Dio>((ref) {
  final coordinator = ref.read(apiRateLimitCoordinatorProvider);
  final dio = Dio();
  // Configure User-Agent header as required by VRChat API
  dio.options.headers['User-Agent'] =
      'Portal/1.0.0 (+https://github.com/onashia/portal)';
  // Add reasonable timeouts to prevent hanging on network issues
  dio.options.connectTimeout = const Duration(seconds: 10);
  dio.options.receiveTimeout = const Duration(seconds: 10);
  ensureApiRateLimitInterceptor(dio, coordinator);
  return dio;
});

final vrchatStatusProvider =
    AsyncNotifierProvider<VrchatStatusNotifier, VrchatStatusState>(
      VrchatStatusNotifier.new,
    );
