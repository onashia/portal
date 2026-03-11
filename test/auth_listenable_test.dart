import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/auth_provider.dart';
import 'test_helpers/auth_test_harness.dart';

void main() {
  test('authListenableProvider notifies only for status transitions', () async {
    final currentUser = mockCurrentUser('usr_test');
    final streamedUser = mockStreamedCurrentUser();

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => TestAuthNotifier(const AuthState(status: AuthStatus.initial)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final authNotifier =
        container.read(authProvider.notifier) as TestAuthNotifier;

    final authListenableSubscription = container.listen(
      authListenableProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(authListenableSubscription.close);
    final listenable = authListenableSubscription.read();
    var notifyCount = 0;
    void listener() {
      notifyCount += 1;
    }

    listenable.addListener(listener);
    addTearDown(() => listenable.removeListener(listener));

    authNotifier.setData(
      AuthState(status: AuthStatus.authenticated, currentUser: currentUser),
    );
    await container.pump();
    expect(notifyCount, 1);

    authNotifier.setData(
      AuthState(
        status: AuthStatus.authenticated,
        currentUser: currentUser,
        streamedUser: streamedUser,
      ),
    );
    await container.pump();
    expect(notifyCount, 1);

    authNotifier.setData(const AuthState(status: AuthStatus.initial));
    await container.pump();
    expect(notifyCount, 2);
  });
}
