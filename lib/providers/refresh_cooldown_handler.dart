import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_rate_limit_coordinator.dart';
import '../utils/app_logger.dart';
import 'api_call_counter.dart';
import 'api_rate_limit_provider.dart';
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

    final coordinator = ref.read(apiRateLimitCoordinatorProvider);
    final remaining = coordinator.remainingCooldown(lane);
    if (remaining != null) {
      AppLogger.debug(
        '$logContext refresh deferred due to cooldown (${remaining.inSeconds}s remaining)',
        subCategory: logContext,
      );
      ref
          .read(apiCallCounterProvider.notifier)
          .incrementThrottledSkip(lane: lane);
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
