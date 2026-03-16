import 'dart:convert';

import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../utils/app_logger.dart';
import '../utils/dio_error_logger.dart';
import '../utils/error_utils.dart';
import 'api_rate_limit_coordinator.dart';
import 'portal_api_request_runner.dart';

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

  AuthResult({required this.status, this.errorMessage, this.currentUser});
}

class AuthService {
  final VrchatDart api;
  final PortalApiRequestRunner _runner;

  AuthService(this.api, {required PortalApiRequestRunner runner})
    : _runner = runner;

  String _basicAuthorizationHeader(String username, String password) {
    final encodedUsername = Uri.encodeComponent(username);
    final encodedPassword = Uri.encodeComponent(password);
    final authorization = base64.encode(
      utf8.encode('$encodedUsername:$encodedPassword'),
    );
    return 'Basic $authorization';
  }

  Future<TransformedResponse<dynamic, AuthResponse>> _performLoginRequest({
    required String username,
    required String password,
    required Map<String, dynamic>? extra,
  }) async {
    final loginResponse = await api.rawApi
        .getAuthenticationApi()
        .getCurrentUser(
          headers: {
            'Authorization': _basicAuthorizationHeader(username, password),
          },
          extra: extra,
        )
        .validateVrc();

    return _transformLoginResponse(loginResponse);
  }

  TransformedResponse<dynamic, AuthResponse> _transformLoginResponse(
    ValidatedResponse<CurrentUser> loginResponse,
  ) {
    final (success, failure) = loginResponse;

    if (success != null) {
      return (ValidResponse(AuthResponse(), success.response), null);
    }

    if (failure != null) {
      return _buildTwoFactorAuthResponse(failure);
    }

    throw StateError('This should never happen');
  }

  TransformedResponse<dynamic, AuthResponse> _buildTwoFactorAuthResponse(
    InvalidResponse failure,
  ) {
    final response = failure.response;
    if (response == null) {
      return (null, failure);
    }

    final twoFactorAuthTypes = _extractTwoFactorAuthTypes(response.data);
    if (twoFactorAuthTypes == null) {
      return (null, failure);
    }

    return (
      ValidResponse(
        AuthResponse(twoFactorAuthTypes: twoFactorAuthTypes),
        response,
      ),
      null,
    );
  }

  List<TwoFactorAuthType>? _extractTwoFactorAuthTypes(Object? data) {
    if (data is! Map<String, dynamic>) {
      return null;
    }

    return (data['requiresTwoFactorAuth'] as List?)
        ?.cast<String>()
        .map(TwoFactorAuthType.values.byName)
        .toList();
  }

  Future<AuthResult> login(String username, String password) async {
    AppLogger.info('Login attempt started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API login', subCategory: 'auth');

      final loginResponse = await _runner
          .runValidatedTransform<dynamic, AuthResponse>(
            lane: ApiRequestLane.authSession,
            request: (extra) => _performLoginRequest(
              username: username,
              password: password,
              extra: extra,
            ),
          );

      AppLogger.debug(
        'API login call completed successfully',
        subCategory: 'auth',
      );

      final (success, failure) = loginResponse;

      if (success == null) {
        final failureSummary = summarizeErrorForLog(failure);
        AppLogger.warning(
          'Login rejected by API: $failureSummary',
          subCategory: 'auth',
        );
        final failureMessage = failure.toString().split('\n').first.trim();
        final errorMessage = formatApiError('Login failed', failure);

        if (failureMessage.contains('Check your email') ||
            failureMessage.contains('logging in from somewhere new')) {
          return AuthResult(
            status: AuthResultStatus.requiresEmailVerification,
            errorMessage: errorMessage,
          );
        }

        return AuthResult(
          status: AuthResultStatus.failure,
          errorMessage: errorMessage,
        );
      }

      final authResponse = success.data;
      if (authResponse.requiresTwoFactorAuth == true) {
        AppLogger.info(
          '2FA is required based on login response',
          subCategory: 'auth',
        );
        return AuthResult(status: AuthResultStatus.requires2FA);
      }

      final currentUser = success.response.data;
      if (currentUser == null) {
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
        return AuthResult(status: AuthResultStatus.requires2FA);
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
      logAuthException('Login', e, s);
      return AuthResult(
        status: AuthResultStatus.failure,
        errorMessage: formatApiError('Login failed', e),
      );
    }
  }

  Future<AuthResult> logout() async {
    AppLogger.info('Logout started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API logout', subCategory: 'auth');

      await _runner.runValidatedTransform<Success, Success>(
        lane: ApiRequestLane.authSession,
        request: (extra) => api.rawApi
            .getAuthenticationApi()
            .logout(extra: extra)
            .validateVrc(),
      );

      AppLogger.info(
        'API logout call completed successfully',
        subCategory: 'auth',
      );

      return AuthResult(status: AuthResultStatus.success);
    } catch (e, s) {
      logAuthException('Logout', e, s);
      return AuthResult(
        status: AuthResultStatus.failure,
        errorMessage: formatApiError('Logout failed', e),
      );
    }
  }

  Future<AuthResult> checkExistingSession() async {
    AppLogger.info('Checking for existing session', subCategory: 'auth');

    try {
      final (success, failure) = await _runner
          .runValidatedTransform<CurrentUser, CurrentUser>(
            lane: ApiRequestLane.authSession,
            request: (extra) => api.rawApi
                .getAuthenticationApi()
                .getCurrentUser(extra: extra)
                .validateVrc(),
          );

      if (success != null && success.response.statusCode == 200) {
        AppLogger.info('Existing session is valid', subCategory: 'auth');
        return AuthResult(
          status: AuthResultStatus.success,
          currentUser: success.data,
        );
      } else {
        AppLogger.info('No valid existing session found', subCategory: 'auth');
        return AuthResult(status: AuthResultStatus.failure);
      }
    } catch (e, s) {
      logAuthException('Check session', e, s);
      return AuthResult(
        status: AuthResultStatus.failure,
        errorMessage: formatApiError('Session check failed', e),
      );
    }
  }
}
