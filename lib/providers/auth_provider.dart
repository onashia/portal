import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

enum AuthStatus {
  initial,
  loading,
  requires2FA,
  authenticated,
  unauthenticated,
  error,
  requiresEmailVerification,
}

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final CurrentUser? currentUser;
  final bool requiresTwoFactorAuth;

  AuthState({
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

class AuthNotifier extends StateNotifier<AuthState> {
  final VrchatDart api;

  AuthNotifier(this.api) : super(AuthState(status: AuthStatus.initial));

  Future<void> login(String username, String password) async {
    state = state.copyWith(status: AuthStatus.loading);

    developer.log(
      'Login attempt started',
      name: 'portal.auth',
      level: 500,
    );
    debugPrint('[AUTH] Login attempt started for username: $username');

    try {
      developer.log(
        'Calling VRChat API login',
        name: 'portal.auth',
        level: 700,
      );
      debugPrint('[AUTH] Calling VRChat API login...');

      final loginResponse = await api.auth.login(
        username: username,
        password: password,
      );

      developer.log(
        'API login call completed successfully',
        name: 'portal.auth',
        level: 700,
      );
      debugPrint('[AUTH] API login call completed successfully');
      debugPrint('[AUTH] Login response: ${loginResponse.toString()}');
      debugPrint('[AUTH] Login response type: ${loginResponse.runtimeType}');

      final currentUser = api.auth.currentUser;
      debugPrint('[AUTH] api.auth.currentUser: $currentUser');

      if (currentUser == null) {
        developer.log(
          'currentUser is null after login - checking loginResponse for 2FA requirement',
          name: 'portal.auth',
          level: 900,
        );
        debugPrint('[AUTH] currentUser is null - checking if 2FA is required');

        debugPrint('[AUTH] loginResponse type: ${loginResponse.runtimeType}');

        final (success, failure) = loginResponse;

        if (success != null) {
          debugPrint('[AUTH] Login response succeeded');
          final authResponse = success.data;
          debugPrint('[AUTH] AuthResponse data: $authResponse');
          debugPrint('[AUTH] AuthResponse data type: ${authResponse.runtimeType}');

          if (authResponse != null) {
            debugPrint('[AUTH] Checking AuthResponse properties for 2FA indicator');
            debugPrint('[AUTH] authResponse.requiresTwoFactorAuth: ${authResponse.requiresTwoFactorAuth}');

            if (authResponse.requiresTwoFactorAuth == true) {
              developer.log(
                  '2FA is required based on login response',
                  name: 'portal.auth',
                  level: 500,
                );
              debugPrint('[AUTH] 2FA is required - transitioning to 2FA screen');
              state = state.copyWith(
                status: AuthStatus.requires2FA,
                requiresTwoFactorAuth: true,
              );
              return;
            } else {
              debugPrint('[AUTH] 2FA is NOT required according to response');
              debugPrint('[AUTH] Response succeeded but currentUser is still null - this is unexpected');
            }
          } else {
            debugPrint('[AUTH] AuthResponse data is null');
          }
        } else {
          debugPrint('[AUTH] Login response failed');
          debugPrint('[AUTH] Failure: $failure');
          developer.log(
            'Login response failed',
            name: 'portal.auth',
            level: 1000,
          );

          final failureMessage = failure.toString().split('\n').first.trim();
          debugPrint('[AUTH] Failure message: $failureMessage');

          final requiresEmailVerification = failureMessage.contains('Check your email') ||
              failureMessage.contains('logging in from somewhere new');

          final errorMessage = 'Login failed: $failureMessage';

          if (requiresEmailVerification) {
            debugPrint('[AUTH] Email verification required');
            state = state.copyWith(
              status: AuthStatus.requiresEmailVerification,
              errorMessage: errorMessage,
            );
          } else {
            debugPrint('[AUTH] Generic login failure');
            state = state.copyWith(
              status: AuthStatus.error,
              errorMessage: errorMessage,
            );
          }
          return;
        }

        developer.log(
          'Login failed: currentUser is null after successful API call and no 2FA indication',
          name: 'portal.auth',
          level: 1000,
        );
        debugPrint('[AUTH] ERROR: currentUser is null after successful API call');
        debugPrint('[AUTH] This likely means 2FA is required but response handling is incomplete');
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: 'Login failed: Could not authenticate',
        );
        return;
      }

      developer.log(
        'User authenticated successfully: ${currentUser.username}',
        name: 'portal.auth',
        level: 500,
      );
      debugPrint('[AUTH] User authenticated successfully: ${currentUser.username}');
      debugPrint('[AUTH] User twoFactorAuthEnabled: ${currentUser.twoFactorAuthEnabled}');

      if (currentUser.twoFactorAuthEnabled) {
        developer.log(
          '2FA is enabled for user: ${currentUser.username}',
          name: 'portal.auth',
          level: 500,
        );
        debugPrint('[AUTH] 2FA is enabled for user: ${currentUser.username}');
        state = state.copyWith(
          status: AuthStatus.requires2FA,
          requiresTwoFactorAuth: true,
        );
      } else {
        developer.log(
          '2FA is not enabled, user fully authenticated: ${currentUser.username}',
          name: 'portal.auth',
          level: 500,
        );
        debugPrint('[AUTH] 2FA is not enabled, user fully authenticated: ${currentUser.username}');
        state = state.copyWith(
          status: AuthStatus.authenticated,
          currentUser: currentUser,
        );
      }
    } catch (e, s) {
      developer.log(
        'Login failed with exception',
        name: 'portal.auth',
        level: 1000,
        error: e,
        stackTrace: s,
      );
      debugPrint('[AUTH] ERROR: Login failed with exception: $e');
      debugPrint('[AUTH] Exception type: ${e.runtimeType}');
      debugPrint('[AUTH] Stack trace: $s');
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'Login failed: ${e.toString()}',
      );
    }
  }

  Future<void> verify2FA(String code) async {
    state = state.copyWith(status: AuthStatus.loading);

    developer.log(
      '2FA verification started',
      name: 'portal.auth',
      level: 500,
    );
    debugPrint('[AUTH] 2FA verification started');

    try {
      developer.log(
        'Calling VRChat API verify2fa',
        name: 'portal.auth',
        level: 700,
      );
      debugPrint('[AUTH] Calling VRChat API verify2fa...');

      final verify2faResponse = await api.auth.verify2fa(code);

      final (success, failure) = verify2faResponse;

      if (failure != null) {
        developer.log(
          '2FA verification failed',
          name: 'portal.auth',
          level: 1000,
        );
        debugPrint('[AUTH] ERROR: 2FA verification failed: $failure');
        state = state.copyWith(
          status: AuthStatus.requires2FA,
          errorMessage: '2FA verification failed: ${failure.toString()}',
        );
        return;
      }

      developer.log(
        'API verify2fa call completed successfully',
        name: 'portal.auth',
        level: 700,
      );
      debugPrint('[AUTH] API verify2fa call completed successfully');

      developer.log(
        'Fetching current user after 2FA verification',
        name: 'portal.auth',
        level: 700,
      );
      debugPrint('[AUTH] Fetching current user after 2FA verification...');

      final currentUser = api.auth.currentUser;
      if (currentUser != null) {
        developer.log(
          '2FA verification successful for user: ${currentUser.displayName}',
          name: 'portal.auth',
          level: 500,
        );
        debugPrint('[AUTH] 2FA verification successful for user: ${currentUser.displayName}');
        state = state.copyWith(
          status: AuthStatus.authenticated,
          currentUser: currentUser,
          errorMessage: null,
        );
      } else {
        developer.log(
          '2FA verification failed: currentUser is null after successful verify2fa',
          name: 'portal.auth',
          level: 1000,
        );
        debugPrint('[AUTH] ERROR: 2FA verification failed - currentUser is null after successful verify2fa');
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: '2FA verification failed: No user data received',
        );
      }
    } catch (e, s) {
      developer.log(
        '2FA verification failed with exception',
        name: 'portal.auth',
        level: 1000,
        error: e,
        stackTrace: s,
      );
      debugPrint('[AUTH] ERROR: 2FA verification failed with exception: $e');
      debugPrint('[AUTH] Stack trace: $s');
      state = state.copyWith(
        status: AuthStatus.requires2FA,
        errorMessage: '2FA verification failed: ${e.toString()}',
      );
    }
  }

  Future<void> logout() async {
    developer.log(
      'Logout started',
      name: 'portal.auth',
      level: 500,
    );
    debugPrint('[AUTH] Logout started');

    try {
      developer.log(
        'Calling VRChat API logout',
        name: 'portal.auth',
        level: 700,
      );
      debugPrint('[AUTH] Calling VRChat API logout...');

      await api.auth.logout();

      developer.log(
        'API logout call completed successfully',
        name: 'portal.auth',
        level: 500,
      );
      debugPrint('[AUTH] API logout call completed successfully');

      state = AuthState(status: AuthStatus.initial);
    } catch (e, s) {
      developer.log(
        'Logout failed with exception',
        name: 'portal.auth',
        level: 1000,
        error: e,
        stackTrace: s,
      );
      debugPrint('[AUTH] ERROR: Logout failed with exception: $e');
      debugPrint('[AUTH] Stack trace: $s');
      state = AuthState(status: AuthStatus.initial);
    }
  }

  Future<void> checkExistingSession() async {
    state = state.copyWith(status: AuthStatus.loading);

    developer.log(
      'Checking for existing session',
      name: 'portal.auth',
      level: 500,
    );
    debugPrint('[AUTH] Checking for existing session...');

    try {
      final currentUser = api.auth.currentUser;
      if (currentUser != null) {
        developer.log(
          'Existing session found for user: ${currentUser.username}',
          name: 'portal.auth',
          level: 500,
        );
        debugPrint('[AUTH] Existing session found for user: ${currentUser.username}');
        state = state.copyWith(
          status: AuthStatus.authenticated,
          currentUser: currentUser,
        );
      } else {
        developer.log(
          'No existing session found',
          name: 'portal.auth',
          level: 500,
        );
        debugPrint('[AUTH] No existing session found');
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } catch (e, s) {
      developer.log(
        'Failed to check existing session with exception',
        name: 'portal.auth',
        level: 1000,
        error: e,
        stackTrace: s,
      );
      debugPrint('[AUTH] ERROR: Failed to check existing session with exception: $e');
      debugPrint('[AUTH] Stack trace: $s');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        errorMessage: e.toString(),
      );
    }
  }
}

final vrchatApiProvider = Provider<VrchatDart>((ref) {
  return VrchatDart(
    userAgent: VrchatUserAgent(
      applicationName: 'Portal',
      version: '1.0.0',
      contactInfo: 'support@portal.app',
    ),
  );
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(vrchatApiProvider);
  return AuthNotifier(api);
});
