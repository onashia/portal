import '../services/api_rate_limit_coordinator.dart';
import '../services/portal_request_runner_common.dart';
import '../utils/app_logger.dart';
import 'polling_lifecycle.dart';

class RefreshCooldownHandler {
  static bool shouldDeferForCooldown({
    required PortalCooldownTracker cooldownTracker,
    required bool bypassRateLimit,
    required ApiRequestLane lane,
    required String logContext,
    required Duration fallbackDelay,
    required void Function(Duration) onDefer,
  }) {
    if (bypassRateLimit) return false;

    final remaining = cooldownTracker.remainingCooldown(lane);
    if (remaining != null) {
      AppLogger.debug(
        '$logContext refresh deferred due to cooldown (${remaining.inSeconds}s remaining)',
        subCategory: logContext,
      );
      cooldownTracker.recordThrottledSkip(lane: lane);
      onDefer(
        resolveCooldownAwareDelay(
          remainingCooldown: remaining,
          fallbackDelay: fallbackDelay,
        ),
      );
      return true;
    }
    return false;
  }
}
