import 'package:dio/dio.dart';

import 'api_rate_limit_coordinator.dart';
import 'portal_request_runner_common.dart';

class PortalStatusRequestRunner implements PortalCooldownTracker {
  PortalStatusRequestRunner({
    required ApiRateLimitCoordinator coordinator,
    required PortalApiCallRecorder recordApiCall,
    required PortalApiCallRecorder recordThrottledSkip,
  }) : _coordinator = coordinator,
       _recordApiCall = recordApiCall,
       _recordThrottledSkip = recordThrottledSkip;

  factory PortalStatusRequestRunner.untracked() {
    return PortalStatusRequestRunner(
      coordinator: ApiRateLimitCoordinator(),
      recordApiCall: ({lane}) {},
      recordThrottledSkip: ({lane}) {},
    );
  }

  final ApiRateLimitCoordinator _coordinator;
  final PortalApiCallRecorder _recordApiCall;
  final PortalApiCallRecorder _recordThrottledSkip;

  @override
  Duration? remainingCooldown(ApiRequestLane lane) {
    return _coordinator.remainingCooldown(lane);
  }

  @override
  void recordThrottledSkip({required ApiRequestLane lane}) {
    _recordThrottledSkip(lane: lane);
  }

  Future<T> run<T>({
    required ApiRequestLane lane,
    required Future<T> Function(Map<String, dynamic>? extra) request,
    Duration? timeout,
    bool attachLaneExtra = true,
  }) async {
    _recordApiCall(lane: lane);

    try {
      final future = request(
        attachLaneExtra ? apiRequestLaneExtra(lane) : null,
      );
      final result = timeout == null
          ? await future
          : await future.timeout(timeout);
      _coordinator.recordSuccess(lane);
      return result;
    } on DioException catch (e) {
      _recordRateLimitedError(lane, e);
      rethrow;
    }
  }

  void _recordRateLimitedError(ApiRequestLane lane, DioException error) {
    if (error.response?.statusCode != 429) {
      return;
    }

    final retryAfter = _coordinator.parseRetryAfterFromHeaders(
      error.response?.headers,
    );
    _coordinator.recordRateLimited(lane, retryAfter: retryAfter);
  }
}
