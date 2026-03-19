import 'api_rate_limit_coordinator.dart';

typedef PortalApiCallRecorder = void Function({ApiRequestLane? lane});

abstract interface class PortalCooldownTracker {
  Duration? remainingCooldown(ApiRequestLane lane);

  void recordThrottledSkip({required ApiRequestLane lane});
}
