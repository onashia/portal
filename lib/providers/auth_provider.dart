import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../utils/app_logger.dart';
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

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  AuthState build() => AuthState(status: AuthStatus.initial);

  Future<void> login(String username, String password) async {
    state = AsyncLoading();

    AppLogger.info('Login attempt started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API login', subCategory: 'auth');

      ref.read(apiCallCounterProvider.notifier).incrementApiCall();

      final api = ref.read(vrchatApiProvider);

      final loginResponse = await api.auth.login(
        username: username,
        password: password,
      );

      AppLogger.debug(
        'API login call completed successfully',
        subCategory: 'auth',
      );

      final currentUser = api.auth.currentUser;

      if (currentUser == null) {
        AppLogger.warning(
          'currentUser is null after login - checking for 2FA',
          subCategory: 'auth',
        );

        final (success, failure) = loginResponse;

        if (success != null) {
          final authResponse = success.data;

          if (authResponse.requiresTwoFactorAuth == true) {
            AppLogger.info(
              '2FA is required based on login response',
              subCategory: 'auth',
            );
            state = AsyncData(
              AuthState(
                status: AuthStatus.requires2FA,
                requiresTwoFactorAuth: true,
              ),
            );
            return;
          }
        } else {
          AppLogger.error('Login response failed', subCategory: 'auth');
          final failureMessage = failure.toString().split('\n').first.trim();
          final requiresEmailVerification =
              failureMessage.contains('Check your email') ||
              failureMessage.contains('logging in from somewhere new');

          final errorMessage = 'Login failed: $failureMessage';

          if (requiresEmailVerification) {
            state = AsyncData(
              AuthState(
                status: AuthStatus.requiresEmailVerification,
                errorMessage: errorMessage,
              ),
            );
          } else {
            state = AsyncData(
              AuthState(status: AuthStatus.error, errorMessage: errorMessage),
            );
          }
          return;
        }

        AppLogger.error(
          'currentUser is null after successful API call',
          subCategory: 'auth',
        );
        state = AsyncData(
          AuthState(
            status: AuthStatus.error,
            errorMessage: 'Login failed: Could not authenticate',
          ),
        );
        return;
      }

      AppLogger.info('User authenticated successfully', subCategory: 'auth');

      if (currentUser.twoFactorAuthEnabled) {
        AppLogger.info('2FA is enabled for user', subCategory: 'auth');
        state = AsyncData(
          AuthState(
            status: AuthStatus.requires2FA,
            requiresTwoFactorAuth: true,
          ),
        );
      } else {
        AppLogger.info(
          '2FA is not enabled, user fully authenticated',
          subCategory: 'auth',
        );
        state = AsyncData(
          AuthState(status: AuthStatus.authenticated, currentUser: currentUser),
        );
      }
    } catch (e, s) {
      AppLogger.error(
        'Login failed with exception',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      state = AsyncData(
        AuthState(
          status: AuthStatus.error,
          errorMessage: 'Login failed: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> verify2FA(String code) async {
    state = AsyncLoading();

    AppLogger.info('2FA verification started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API verify2fa', subCategory: 'auth');

      ref.read(apiCallCounterProvider.notifier).incrementApiCall();

      final api = ref.read(vrchatApiProvider);
      final verify2faResponse = await api.auth.verify2fa(code);

      final (success, failure) = verify2faResponse;

      if (failure != null) {
        AppLogger.error('2FA verification failed', subCategory: 'auth');
        state = AsyncData(
          AuthState(
            status: AuthStatus.requires2FA,
            errorMessage: '2FA verification failed: ${failure.toString()}',
          ),
        );
        return;
      }

      AppLogger.debug(
        'API verify2fa call completed successfully',
        subCategory: 'auth',
      );

      final currentUser = api.auth.currentUser;
      if (currentUser != null) {
        AppLogger.info('2FA verification successful', subCategory: 'auth');
        state = AsyncData(
          AuthState(
            status: AuthStatus.authenticated,
            currentUser: currentUser,
            errorMessage: null,
          ),
        );
      } else {
        AppLogger.error(
          'currentUser is null after successful verify2fa',
          subCategory: 'auth',
        );
        state = AsyncData(
          AuthState(
            status: AuthStatus.error,
            errorMessage: '2FA verification failed: No user data received',
          ),
        );
      }
    } catch (e, s) {
      AppLogger.error(
        '2FA verification failed with exception',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      state = AsyncData(
        AuthState(
          status: AuthStatus.requires2FA,
          errorMessage: '2FA verification failed: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> logout() async {
    AppLogger.info('Logout started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API logout', subCategory: 'auth');

      ref.read(apiCallCounterProvider.notifier).incrementApiCall();

      final api = ref.read(vrchatApiProvider);
      await api.auth.logout();

      AppLogger.info(
        'API logout call completed successfully',
        subCategory: 'auth',
      );

      state = AsyncData(AuthState(status: AuthStatus.initial));
    } catch (e, s) {
      AppLogger.error(
        'Logout failed with exception',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      state = AsyncData(AuthState(status: AuthStatus.initial));
    }
  }

  Future<void> checkExistingSession() async {
    state = AsyncLoading();

    AppLogger.info('Checking for existing session', subCategory: 'auth');

    try {
      final api = ref.read(vrchatApiProvider);
      final currentUser = api.auth.currentUser;
      if (currentUser != null) {
        AppLogger.info('Existing session found', subCategory: 'auth');
        state = AsyncData(
          AuthState(status: AuthStatus.authenticated, currentUser: currentUser),
        );
      } else {
        AppLogger.info('No existing session found', subCategory: 'auth');
        state = AsyncData(AuthState(status: AuthStatus.unauthenticated));
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to check existing session',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      state = AsyncData(
        AuthState(
          status: AuthStatus.unauthenticated,
          errorMessage: e.toString(),
        ),
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

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
