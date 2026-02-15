import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/polling_lifecycle.dart';

void main() {
  group('resolveCooldownAwareDelay', () {
    test('returns fallback delay when cooldown is absent', () {
      final delay = resolveCooldownAwareDelay(
        remainingCooldown: null,
        fallbackDelay: const Duration(seconds: 10),
      );

      expect(delay, const Duration(seconds: 10));
    });

    test('returns cooldown plus safety buffer when cooldown is present', () {
      final delay = resolveCooldownAwareDelay(
        remainingCooldown: const Duration(seconds: 3),
        fallbackDelay: const Duration(seconds: 10),
      );

      expect(delay, const Duration(seconds: 3, milliseconds: 250));
    });

    test('returns safety buffer when cooldown is zero or negative', () {
      final zeroDelay = resolveCooldownAwareDelay(
        remainingCooldown: Duration.zero,
        fallbackDelay: const Duration(seconds: 10),
      );
      final negativeDelay = resolveCooldownAwareDelay(
        remainingCooldown: const Duration(milliseconds: -1),
        fallbackDelay: const Duration(seconds: 10),
      );

      expect(zeroDelay, const Duration(milliseconds: 250));
      expect(negativeDelay, const Duration(milliseconds: 250));
    });

    test('supports custom safety buffer override', () {
      final delay = resolveCooldownAwareDelay(
        remainingCooldown: const Duration(milliseconds: 100),
        fallbackDelay: const Duration(seconds: 10),
        safetyBuffer: const Duration(milliseconds: 500),
      );

      expect(delay, const Duration(milliseconds: 600));
    });
  });
}
