import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/auth_provider.dart';
import 'test_helpers/auth_test_harness.dart';

void main() {
  test('selectors map auth slices and async metadata', () {
    final currentUser = mockCurrentUser('usr_test');
    final streamedUser = mockStreamedCurrentUser();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => TestAuthNotifier(
            AuthState(
              status: AuthStatus.authenticated,
              currentUser: currentUser,
              streamedUser: streamedUser,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(authProvider.notifier) as TestAuthNotifier;

    expect(container.read(authStatusProvider), AuthStatus.authenticated);
    expect(container.read(authCurrentUserProvider), same(currentUser));
    expect(container.read(authStreamedUserProvider), same(streamedUser));
    final authenticatedSession = container.read(authSessionSnapshotProvider);
    expect(authenticatedSession.status, AuthStatus.authenticated);
    expect(authenticatedSession.isAuthenticated, isTrue);
    expect(authenticatedSession.userId, 'usr_test');

    notifier.setLoading();
    final loadingMeta = container.read(authAsyncMetaProvider);
    expect(loadingMeta.isLoading, isTrue);
    expect(loadingMeta.hasError, isFalse);
    expect(loadingMeta.error, isNull);

    final error = StateError('boom');
    notifier.setError(error, StackTrace.current);
    final errorMeta = container.read(authAsyncMetaProvider);
    expect(errorMeta.isLoading, isFalse);
    expect(errorMeta.hasError, isTrue);
    expect(errorMeta.error, same(error));
    final errorSession = container.read(authSessionSnapshotProvider);
    expect(errorSession.status, isNull);
    expect(errorSession.isAuthenticated, isFalse);
    expect(errorSession.userId, isNull);
  });

  test(
    'authStatusProvider does not emit for non-status auth updates',
    () async {
      final currentUser = mockCurrentUser('usr_test');
      final firstStreamedUser = mockStreamedCurrentUser();
      final secondStreamedUser = mockStreamedCurrentUser();
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => TestAuthNotifier(const AuthState(status: AuthStatus.initial)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final notifier =
          container.read(authProvider.notifier) as TestAuthNotifier;

      final observedStatuses = <AuthStatus?>[];
      final subscription = container.listen<AuthStatus?>(authStatusProvider, (
        previous,
        next,
      ) {
        observedStatuses.add(next);
      }, fireImmediately: true);
      addTearDown(subscription.close);

      final observedSessions = <AuthSessionSnapshot>[];
      final sessionSubscription = container.listen<AuthSessionSnapshot>(
        authSessionSnapshotProvider,
        (_, next) => observedSessions.add(next),
        fireImmediately: true,
      );
      addTearDown(sessionSubscription.close);

      notifier.setData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: currentUser,
          streamedUser: firstStreamedUser,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      notifier.setData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: currentUser,
          streamedUser: secondStreamedUser,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(observedStatuses, [AuthStatus.initial, AuthStatus.authenticated]);
      expect(observedSessions.first.isAuthenticated, isFalse);
      expect(observedSessions.last.isAuthenticated, isTrue);
    },
  );
}
