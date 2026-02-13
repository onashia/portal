import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._initialState);

  final AuthState _initialState;

  @override
  AuthState build() => _initialState;

  void setData(AuthState next) {
    state = AsyncData(next);
  }
}

class _MockCurrentUser extends Mock implements CurrentUser {}

class _MockStreamedCurrentUser extends Mock implements StreamedCurrentUser {}

void main() {
  test('authListenableProvider notifies only for status transitions', () async {
    final currentUser = _MockCurrentUser();
    final streamedUser = _MockStreamedCurrentUser();

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _TestAuthNotifier(const AuthState(status: AuthStatus.initial)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final authNotifier =
        container.read(authProvider.notifier) as _TestAuthNotifier;

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
