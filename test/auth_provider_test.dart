import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/auth_provider.dart';

import 'test_helpers/auth_test_harness.dart';

void main() {
  test(
    'verify2FA keeps the user in 2FA state when the verification method is missing',
    () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => TestAuthNotifier(
              const AuthState(
                status: AuthStatus.requires2FA,
                requiresTwoFactorAuth: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier =
          container.read(authProvider.notifier) as TestAuthNotifier;

      await notifier.verify2FA('123456');

      final state = container.read(authProvider).value;
      expect(state?.status, AuthStatus.requires2FA);
      expect(state?.requiresTwoFactorAuth, isTrue);
      expect(
        state?.errorMessage,
        '2FA verification failed: Could not determine verification method',
      );
    },
  );
}
