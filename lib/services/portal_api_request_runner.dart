import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dio_response_validator/dio_response_validator.dart';

import 'api_rate_limit_coordinator.dart';
import 'portal_request_runner_common.dart';

class _InFlightReadRequest {
  const _InFlightReadRequest({required this.resultType, required this.future});

  final Type resultType;
  final Future<Object?> future;
}

class PortalApiRequestRunner implements PortalCooldownTracker {
  PortalApiRequestRunner({
    required ApiRateLimitCoordinator coordinator,
    required PortalApiCallRecorder recordApiCall,
    required PortalApiCallRecorder recordThrottledSkip,
  }) : _coordinator = coordinator,
       _recordApiCall = recordApiCall,
       _recordThrottledSkip = recordThrottledSkip;

  factory PortalApiRequestRunner.untracked() {
    return PortalApiRequestRunner(
      coordinator: ApiRateLimitCoordinator(),
      recordApiCall: ({lane}) {},
      recordThrottledSkip: ({lane}) {},
    );
  }

  final ApiRateLimitCoordinator _coordinator;
  final PortalApiCallRecorder _recordApiCall;
  final PortalApiCallRecorder _recordThrottledSkip;
  final Map<String, _InFlightReadRequest> _inFlightReadRequests =
      <String, _InFlightReadRequest>{};

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

  Future<T> runWithReadDedupe<T>({
    required String dedupeKey,
    required ApiRequestLane lane,
    required Future<T> Function(Map<String, dynamic>? extra) request,
    Duration? timeout,
    bool attachLaneExtra = true,
  }) {
    final inFlight = _inFlightReadRequests[dedupeKey];
    if (inFlight != null) {
      if (inFlight.resultType != T) {
        throw StateError(
          'Dedupe key "$dedupeKey" is already in use for '
          '${inFlight.resultType}; cannot reuse it for $T.',
        );
      }
      return inFlight.future as Future<T>;
    }

    final future = run<T>(
      lane: lane,
      request: request,
      timeout: timeout,
      attachLaneExtra: attachLaneExtra,
    );
    final inFlightRequest = _InFlightReadRequest(resultType: T, future: future);
    _inFlightReadRequests[dedupeKey] = inFlightRequest;
    return future.whenComplete(() {
      if (identical(_inFlightReadRequests[dedupeKey], inFlightRequest)) {
        _inFlightReadRequests.remove(dedupeKey);
      }
    });
  }

  Future<TransformedResponse<U, T>> runValidatedTransform<U, T>({
    required ApiRequestLane lane,
    required Future<TransformedResponse<U, T>> Function(
      Map<String, dynamic>? extra,
    )
    request,
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
      _recordValidatedOutcome(
        lane: lane,
        successResponse: result.$1?.response,
        failureResponse: result.$2?.response,
      );
      return result;
    } on DioException catch (e) {
      _recordRateLimitedError(lane, e);
      rethrow;
    }
  }

  void _recordValidatedOutcome({
    required ApiRequestLane lane,
    Response? successResponse,
    Response? failureResponse,
  }) {
    final statusCode =
        successResponse?.statusCode ?? failureResponse?.statusCode;
    if (statusCode == null) {
      return;
    }

    if (statusCode == 429) {
      final retryAfter = _coordinator.parseRetryAfterFromHeaders(
        failureResponse?.headers,
      );
      _coordinator.recordRateLimited(lane, retryAfter: retryAfter);
      return;
    }

    _coordinator.recordSuccess(lane);
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
