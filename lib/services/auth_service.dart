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
  final TwoFactorAuthType? selectedTwoFactorMethod;

  AuthResult({
    required this.status,
    this.errorMessage,
    this.currentUser,
    this.selectedTwoFactorMethod,
  });
}

class AuthService {
  final VrchatDart api;
  final PortalApiRequestRunner _runner;

  AuthService(this.api, {required PortalApiRequestRunner runner})
    : _runner = runner;

  static const String _unsupportedTwoFactorMessage =
      'Unsupported VRChat 2FA challenge';
  static const String _unsupportedRecoveryCodeMessage =
      'Portal does not accept VRChat recovery codes. Recovery codes are '
      'single-use emergency credentials. Please sign in with them through '
      'the official VRChat website or VRChat client.';

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

    final parsed = _extractTwoFactorAuthTypes(response.data);
    if (parsed == null) {
      return (null, failure);
    }

    if (parsed.unsupportedTypes.isNotEmpty) {
      AppLogger.warning(
        'Login response included unsupported 2FA types: '
        '${parsed.unsupportedTypes.join(', ')}',
        subCategory: 'auth',
      );
    }

    if (parsed.malformedTypes.isNotEmpty) {
      AppLogger.warning(
        'Login response included non-string 2FA types: '
        '${parsed.malformedTypes.join(', ')}',
        subCategory: 'auth',
      );
    }

    if (parsed.recoveryCodeTypes.isNotEmpty) {
      AppLogger.warning(
        'Login response included recovery-code 2FA, which Portal '
        'intentionally rejects because recovery codes are single-use '
        'emergency credentials: '
        '${parsed.recoveryCodeTypes.map((type) => type.name).join(', ')}',
        subCategory: 'auth',
      );
    }

    if (parsed.supportedTypes.isEmpty) {
      AppLogger.warning(
        'Login response included no supported 2FA types',
        subCategory: 'auth',
      );
      final errorMessage = parsed.recoveryCodeTypes.isNotEmpty
          ? _unsupportedRecoveryCodeMessage
          : _unsupportedTwoFactorMessage;
      return (
        null,
        InvalidResponse(errorMessage, StackTrace.current, response: response),
      );
    }

    return (
      ValidResponse(
        AuthResponse(twoFactorAuthTypes: parsed.supportedTypes),
        response,
      ),
      null,
    );
  }

  _ParsedTwoFactorAuthTypes? _extractTwoFactorAuthTypes(Object? data) {
    if (data is! Map<String, dynamic>) {
      return null;
    }

    if (!data.containsKey('requiresTwoFactorAuth')) {
      return null;
    }

    final rawTypes = data['requiresTwoFactorAuth'];
    if (rawTypes is! List) {
      return null;
    }

    final supportedTypes = <TwoFactorAuthType>[];
    final unsupportedTypes = <String>[];
    final malformedTypes = <Object?>[];
    final recoveryCodeTypes = <TwoFactorAuthType>[];

    for (final rawType in rawTypes) {
      if (rawType is! String) {
        malformedTypes.add(rawType);
        continue;
      }

      final supportedType = _twoFactorAuthTypeFromName(rawType);
      if (supportedType == null) {
        unsupportedTypes.add(rawType);
        continue;
      }

      if (supportedType == TwoFactorAuthType.otp) {
        recoveryCodeTypes.add(supportedType);
        continue;
      }

      supportedTypes.add(supportedType);
    }

    return _ParsedTwoFactorAuthTypes(
      supportedTypes: supportedTypes,
      unsupportedTypes: unsupportedTypes,
      malformedTypes: malformedTypes,
      recoveryCodeTypes: recoveryCodeTypes,
    );
  }

  TwoFactorAuthType? _twoFactorAuthTypeFromName(String rawType) {
    for (final type in TwoFactorAuthType.values) {
      if (type.name == rawType) {
        return type;
      }
    }
    return null;
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
        final errorMessage =
            failureMessage == _unsupportedRecoveryCodeMessage
            ? 'Login failed: $failureMessage'
            : formatApiError('Login failed', failure);

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
        final availableTwoFactorMethods = authResponse.twoFactorAuthTypes;
        return AuthResult(
          status: AuthResultStatus.requires2FA,
          selectedTwoFactorMethod:
              availableTwoFactorMethods.contains(TwoFactorAuthType.totp)
              ? TwoFactorAuthType.totp
              : availableTwoFactorMethods.first,
        );
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
        return AuthResult(
          status: AuthResultStatus.requires2FA,
          selectedTwoFactorMethod: TwoFactorAuthType.totp,
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

class _ParsedTwoFactorAuthTypes {
  const _ParsedTwoFactorAuthTypes({
    required this.supportedTypes,
    required this.unsupportedTypes,
    required this.malformedTypes,
    required this.recoveryCodeTypes,
  });

  final List<TwoFactorAuthType> supportedTypes;
  final List<String> unsupportedTypes;
  final List<Object?> malformedTypes;
  final List<TwoFactorAuthType> recoveryCodeTypes;
}
