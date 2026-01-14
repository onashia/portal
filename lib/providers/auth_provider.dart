import 'package:flutter/foundation.dart';
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
  final bool requiresTwoFactorAuth;

  const AuthState({
    required this.status,
    this.errorMessage,
    this.currentUser,
    this.requiresTwoFactorAuth = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    CurrentUser? currentUser,
    bool? requiresTwoFactorAuth,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      currentUser: currentUser ?? this.currentUser,
      requiresTwoFactorAuth:
          requiresTwoFactorAuth ?? this.requiresTwoFactorAuth,
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
    return AuthState(status: AuthStatus.initial);
  }

  Future<void> login(String username, String password) async {
    state = AsyncLoading();

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
          ),
        );
        break;
      case AuthResultStatus.requires2FA:
        state = AsyncData(
          AuthState(
            status: AuthStatus.requires2FA,
            requiresTwoFactorAuth: true,
          ),
        );
        break;
      case AuthResultStatus.requiresEmailVerification:
        state = AsyncData(
          AuthState(
            status: AuthStatus.requiresEmailVerification,
            errorMessage: result.errorMessage,
          ),
        );
        break;
      case AuthResultStatus.failure:
        state = AsyncData(
          AuthState(
            status: AuthStatus.error,
            errorMessage: result.errorMessage,
          ),
        );
        break;
    }
  }

  Future<void> verify2FA(String code) async {
    state = AsyncLoading();

    ref.read(apiCallCounterProvider.notifier).incrementApiCall();

    final result = await _twoFactorAuthService.verify2FA(code);

    if (result.status == TwoFactorAuthResultStatus.success) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: result.currentUser,
        ),
      );
    } else {
      state = AsyncData(
        AuthState(
          status: AuthStatus.requires2FA,
          requiresTwoFactorAuth: true,
          errorMessage: result.errorMessage,
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
}

final vrchatApiProvider = Provider<VrchatDart>((ref) {
  // Single shared API instance for the entire application
  // This ensures authentication state is shared across all providers
  return VrchatDart(
    userAgent: VrchatUserAgent(
      applicationName: 'portal.',
      version: '1.0.0',
      contactInfo: 'hails-pixels-9w@icloud.com',
    ),
  );
});

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
