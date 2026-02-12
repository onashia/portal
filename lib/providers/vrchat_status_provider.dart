import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vrchat_status.dart';
import '../services/vrchat_status_service.dart';
import '../utils/timing_utils.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';

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

  @override
  VrchatStatusState build() {
    _service = VrchatStatusService(ref.read(dioProvider));

    // Initial fetch happens immediately
    refresh();

    // Register timer cleanup on dispose
    ref.onDispose(_disposeTimer);

    return const VrchatStatusState(isLoading: true);
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();

    final delay = TimingUtils.durationWithJitter(
      baseSeconds: AppConstants.vrchatStatusPollingIntervalSeconds,
      jitterSeconds: AppConstants.vrchatStatusPollingJitterSeconds,
    );

    _refreshTimer = Timer(delay, () async {
      await refresh();
      _scheduleNextRefresh();
    });
  }

  Future<void> refresh() async {
    try {
      AppLogger.info('Refreshing VRChat status', subCategory: 'vrchat_status');
      final status = await _service.fetchStatus();
      state = AsyncData(VrchatStatusState(status: status, isLoading: false));

      // Schedule next refresh after successful fetch
      _scheduleNextRefresh();
    } catch (e, s) {
      AppLogger.error(
        'VRChat status refresh failed',
        subCategory: 'vrchat_status',
        error: e,
        stackTrace: s,
      );
      state = AsyncData(
        VrchatStatusState(isLoading: false, errorMessage: e.toString()),
      );

      // Still schedule next refresh even on error
      _scheduleNextRefresh();
    }
  }

  void _disposeTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio();
  // Configure User-Agent header as required by VRChat API
  dio.options.headers['User-Agent'] =
      'Portal/1.0.0 (+https://github.com/onashia/portal)';
  // Add reasonable timeouts to prevent hanging on network issues
  dio.options.connectTimeout = const Duration(seconds: 10);
  dio.options.receiveTimeout = const Duration(seconds: 10);
  return dio;
});

final vrchatStatusProvider =
    AsyncNotifierProvider<VrchatStatusNotifier, VrchatStatusState>(
      VrchatStatusNotifier.new,
    );
