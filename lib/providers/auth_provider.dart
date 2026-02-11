import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../services/auth_service.dart';
import '../services/two_factor_auth_service.dart';
import 'api_call_counter.dart';

enum AuthStatus {
  initial,
  loading,
  requires2FA,
  authenticated,
  unauthenticated,
  error,
  requiresEmailVerification,
}

@immutable
class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final CurrentUser? currentUser;
  final StreamedCurrentUser? streamedUser;
  final bool requiresTwoFactorAuth;
  final bool isLoading;

  const AuthState({
    required this.status,
    this.errorMessage,
    this.currentUser,
    this.streamedUser,
    this.requiresTwoFactorAuth = false,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    CurrentUser? currentUser,
    StreamedCurrentUser? streamedUser,
    bool? requiresTwoFactorAuth,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      currentUser: currentUser ?? this.currentUser,
      streamedUser: streamedUser ?? this.streamedUser,
      requiresTwoFactorAuth:
          requiresTwoFactorAuth ?? this.requiresTwoFactorAuth,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  late final AuthService _authService;
  late final TwoFactorAuthService _twoFactorAuthService;

  @override
  AuthState build() {
    final api = ref.read(vrchatApiProvider);
    _authService = AuthService(api);
    _twoFactorAuthService = TwoFactorAuthService(api);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isTest = WidgetsBinding.instance.toString().contains('Test');
      if (!isTest) {
        checkExistingSession();
      }
    });

    return AuthState(status: AuthStatus.initial);
  }

  Future<void> login(String username, String password) async {
    state = AsyncData(AuthState(status: AuthStatus.initial, isLoading: true));

    ref.read(apiCallCounterProvider.notifier).incrementApiCall();

    final result = await _authService.login(username, password);

    // Handle all possible authentication outcomes
    // VRChat API may require 2FA, email verification, or fail with error
    switch (result.status) {
      case AuthResultStatus.success:
        state = AsyncData(
          AuthState(
            status: AuthStatus.authenticated,
            currentUser: result.currentUser,
            isLoading: false,
          ),
        );
        break;
      case AuthResultStatus.requires2FA:
        state = AsyncData(
          AuthState(
            status: AuthStatus.requires2FA,
            requiresTwoFactorAuth: true,
            isLoading: false,
          ),
        );
        break;
      case AuthResultStatus.requiresEmailVerification:
        state = AsyncData(
          AuthState(
            status: AuthStatus.requiresEmailVerification,
            errorMessage: result.errorMessage,
            isLoading: false,
          ),
        );
        break;
      case AuthResultStatus.failure:
        state = AsyncData(
          AuthState(
            status: AuthStatus.error,
            errorMessage: result.errorMessage,
            isLoading: false,
          ),
        );
        break;
    }
  }

  Future<void> verify2FA(String code) async {
    state = AsyncData(
      AuthState(
        status: AuthStatus.requires2FA,
        requiresTwoFactorAuth: true,
        isLoading: true,
      ),
    );

    ref.read(apiCallCounterProvider.notifier).incrementApiCall();

    final result = await _twoFactorAuthService.verify2FA(code);

    if (result.status == TwoFactorAuthResultStatus.success) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: result.currentUser,
          isLoading: false,
        ),
      );
    } else {
      state = AsyncData(
        AuthState(
          status: AuthStatus.requires2FA,
          requiresTwoFactorAuth: true,
          errorMessage: result.errorMessage,
          isLoading: false,
        ),
      );
    }
  }

  Future<void> logout() async {
    ref.read(apiCallCounterProvider.notifier).incrementApiCall();

    await _authService.logout();

    state = AsyncData(AuthState(status: AuthStatus.initial));
  }

  Future<void> checkExistingSession() async {
    state = AsyncLoading();

    final result = await _authService.checkExistingSession();

    if (result.status == AuthResultStatus.success) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: result.currentUser,
        ),
      );
    } else {
      state = AsyncData(AuthState(status: AuthStatus.unauthenticated));
    }
  }

  void updateCurrentUser(StreamedCurrentUser user) {
    final current = state.asData?.value;
    if (current == null || current.status != AuthStatus.authenticated) {
      return;
    }

    state = AsyncData(current.copyWith(streamedUser: user));
  }
}

final vrchatApiProvider = Provider<VrchatDart>((ref) {
  // Single shared API instance for the entire application
  // This ensures authentication state is shared across all providers
  return VrchatDart(
    userAgent: VrchatUserAgent(
      applicationName: 'portal.',
      version: '1.0.0',
      contactInfo: 'https://github.com/onashia/portal',
    ),
  );
});

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

final authListenableProvider = Provider<ChangeNotifier>((ref) {
  return _AuthChangeNotifier(ref);
});

class _AuthChangeNotifier extends ChangeNotifier {
  final Ref _ref;

  _AuthChangeNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthState>>(
      authProvider,
      (previous, next) => notifyListeners(),
    );
  }
}
