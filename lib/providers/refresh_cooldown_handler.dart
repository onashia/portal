import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_rate_limit_coordinator.dart';
import '../utils/app_logger.dart';
import 'portal_api_request_runner_provider.dart';
import 'polling_lifecycle.dart';

class RefreshCooldownHandler {
  static bool shouldDeferForCooldown({
    required Ref ref,
    required bool bypassRateLimit,
    required ApiRequestLane lane,
    required String logContext,
    required Duration fallbackDelay,
    required void Function(Duration) onDefer,
  }) {
    if (bypassRateLimit) return false;

    final runner = ref.read(portalApiRequestRunnerProvider);
    final remaining = runner.remainingCooldown(lane);
    if (remaining != null) {
      AppLogger.debug(
        '$logContext refresh deferred due to cooldown (${remaining.inSeconds}s remaining)',
        subCategory: logContext,
      );
      runner.recordThrottledSkip(lane: lane);
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
