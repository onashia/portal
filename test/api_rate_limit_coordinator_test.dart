import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';

void main() {
  group('ApiRateLimitCoordinator', () {
    test('parses Retry-After seconds', () {
      final now = DateTime.utc(2026, 2, 14, 12, 0, 0);
      final coordinator = ApiRateLimitCoordinator(nowProvider: () => now);

      final parsed = coordinator.parseRetryAfter('45');

      expect(parsed, const Duration(seconds: 45));
    });

    test('parses Retry-After HTTP-date', () {
      final now = DateTime.utc(2026, 2, 14, 12, 0, 0);
      final coordinator = ApiRateLimitCoordinator(nowProvider: () => now);
      final target = now.add(const Duration(seconds: 30));

      final parsed = coordinator.parseRetryAfter(HttpDate.format(target));

      expect(parsed, isNotNull);
      expect(parsed!.inSeconds, inInclusiveRange(29, 30));
    });

    test('uses fallback exponential backoff and caps at max', () {
      final now = DateTime.utc(2026, 2, 14, 12, 0, 0);
      final coordinator = ApiRateLimitCoordinator(nowProvider: () => now);

      coordinator.recordRateLimited(ApiRequestLane.groupBaseline);
      expect(
        coordinator.remainingCooldown(ApiRequestLane.groupBaseline, now: now),
        const Duration(seconds: 20),
      );

      coordinator.recordRateLimited(ApiRequestLane.groupBaseline);
      expect(
        coordinator.remainingCooldown(ApiRequestLane.groupBaseline, now: now),
        const Duration(seconds: 40),
      );

      coordinator.recordRateLimited(ApiRequestLane.groupBaseline);
      expect(
        coordinator.remainingCooldown(ApiRequestLane.groupBaseline, now: now),
        const Duration(seconds: 80),
      );

      coordinator.recordRateLimited(ApiRequestLane.groupBaseline);
      expect(
        coordinator.remainingCooldown(ApiRequestLane.groupBaseline, now: now),
        const Duration(seconds: 120),
      );

      coordinator.recordRateLimited(ApiRequestLane.groupBaseline);
      expect(
        coordinator.remainingCooldown(ApiRequestLane.groupBaseline, now: now),
        const Duration(seconds: 120),
      );
    });

    test('tracks cooldown per lane independently', () {
      final now = DateTime.utc(2026, 2, 14, 12, 0, 0);
      final coordinator = ApiRateLimitCoordinator(nowProvider: () => now);

      coordinator.recordRateLimited(ApiRequestLane.groupBoost);

      expect(
        coordinator.canRequest(ApiRequestLane.groupBaseline, now: now),
        isTrue,
      );
      expect(
        coordinator.canRequest(ApiRequestLane.groupBoost, now: now),
        isFalse,
      );
    });
  });
}
