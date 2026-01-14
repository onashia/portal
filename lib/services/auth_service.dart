import 'package:vrchat_dart/vrchat_dart.dart';
import '../utils/app_logger.dart';

enum AuthResultStatus {
  success,
  requires2FA,
  requiresEmailVerification,
  failure,
}

class AuthResult {
  final AuthResultStatus status;
  final String? errorMessage;
  final CurrentUser? currentUser;

  AuthResult({
    required this.status,
    this.errorMessage,
    this.currentUser,
  });
}

class AuthService {
  final VrchatDart api;

  AuthService(this.api);

  Future<AuthResult> login(String username, String password) async {
    AppLogger.info('Login attempt started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API login', subCategory: 'auth');

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
            return AuthResult(
              status: AuthResultStatus.requires2FA,
            );
          }
        } else {
          AppLogger.error('Login response failed', subCategory: 'auth');
          final failureMessage = failure.toString().split('\n').first.trim();
          final requiresEmailVerification =
              failureMessage.contains('Check your email') ||
              failureMessage.contains('logging in from somewhere new');

          final errorMessage = 'Login failed: $failureMessage';

          if (requiresEmailVerification) {
            return AuthResult(
              status: AuthResultStatus.requiresEmailVerification,
              errorMessage: errorMessage,
            );
          } else {
            return AuthResult(
              status: AuthResultStatus.failure,
              errorMessage: errorMessage,
            );
          }
        }

        AppLogger.error(
          'currentUser is null after successful API call',
          subCategory: 'auth',
        );
        return AuthResult(
          status: AuthResultStatus.failure,
          errorMessage: 'Login failed: Could not authenticate',
        );
      }

      AppLogger.info('User authenticated successfully', subCategory: 'auth');

      if (currentUser.twoFactorAuthEnabled) {
        AppLogger.info('2FA is enabled for user', subCategory: 'auth');
        return AuthResult(
          status: AuthResultStatus.requires2FA,
        );
      } else {
        AppLogger.info(
          '2FA is not enabled, user fully authenticated',
          subCategory: 'auth',
        );
        return AuthResult(
          status: AuthResultStatus.success,
          currentUser: currentUser,
        );
      }
    } catch (e, s) {
      AppLogger.error(
        'Login failed with exception',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      return AuthResult(
        status: AuthResultStatus.failure,
        errorMessage: 'Login failed: ${e.toString()}',
      );
    }
  }

  Future<AuthResult> logout() async {
    AppLogger.info('Logout started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API logout', subCategory: 'auth');

      await api.auth.logout();

      AppLogger.info(
        'API logout call completed successfully',
        subCategory: 'auth',
      );

      return AuthResult(
        status: AuthResultStatus.success,
      );
    } catch (e, s) {
      AppLogger.error(
        'Logout failed with exception',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      return AuthResult(
        status: AuthResultStatus.failure,
        errorMessage: 'Logout failed: ${e.toString()}',
      );
    }
  }

  Future<AuthResult> checkExistingSession() async {
    AppLogger.info('Checking for existing session', subCategory: 'auth');

    try {
      final currentUser = api.auth.currentUser;

      if (currentUser != null) {
        AppLogger.info('Existing session found', subCategory: 'auth');
        return AuthResult(
          status: AuthResultStatus.success,
          currentUser: currentUser,
        );
      } else {
        AppLogger.info('No existing session found', subCategory: 'auth');
        return AuthResult(
          status: AuthResultStatus.failure,
        );
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to check existing session',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      return AuthResult(
        status: AuthResultStatus.failure,
        errorMessage: e.toString(),
      );
    }
  }
}
