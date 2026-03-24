import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/providers/app_version_provider.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

const testAppVersion = '9.9.9';

class TestAuthNotifier extends AuthNotifier {
  TestAuthNotifier(this._initialState);

  final AuthState _initialState;

  @override
  AuthState build() => _initialState;

  void setData(AuthState next) {
    state = AsyncData(next);
  }

  void setLoading() {
    state = const AsyncLoading<AuthState>();
  }

  void setError(Object error, StackTrace stackTrace) {
    state = AsyncError<AuthState>(error, stackTrace);
  }
}

class _MockCurrentUser extends Mock implements CurrentUser {}

class _MockStreamedCurrentUser extends Mock implements StreamedCurrentUser {}

CurrentUser mockCurrentUser(String id) {
  final user = _MockCurrentUser();
  when(() => user.id).thenReturn(id);
  return user;
}

StreamedCurrentUser mockStreamedCurrentUser() {
  return _MockStreamedCurrentUser();
}

AuthState authenticatedAuthState({required String userId}) {
  return AuthState(
    status: AuthStatus.authenticated,
    currentUser: mockCurrentUser(userId),
  );
}

AuthState unauthenticatedAuthState() {
  return const AuthState(status: AuthStatus.unauthenticated);
}

({ProviderContainer container, TestAuthNotifier authNotifier})
createAuthHarness({
  required AuthState initialAuthState,
  List<dynamic> overrides = const <dynamic>[],
}) {
  final authNotifier = TestAuthNotifier(initialAuthState);
  final container = ProviderContainer(
    overrides: [
      appVersionProvider.overrideWithValue(testAppVersion),
      authProvider.overrideWith(() => authNotifier),
      ...overrides,
    ],
  );
  return (container: container, authNotifier: authNotifier);
}
