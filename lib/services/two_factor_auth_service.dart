import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../utils/app_logger.dart';
import '../utils/dio_error_logger.dart';
import '../utils/error_utils.dart';
import 'api_rate_limit_coordinator.dart';
import 'portal_api_request_runner.dart';

enum TwoFactorAuthResultStatus { success, failure }

class TwoFactorAuthResult {
  final TwoFactorAuthResultStatus status;
  final String? errorMessage;
  final CurrentUser? currentUser;

  TwoFactorAuthResult({
    required this.status,
    this.errorMessage,
    this.currentUser,
  });
}

class TwoFactorAuthService {
  final VrchatDart api;
  final PortalApiRequestRunner _runner;

  TwoFactorAuthService(this.api, {PortalApiRequestRunner? runner})
    : _runner = runner ?? PortalApiRequestRunner.untracked();

  Future<TwoFactorAuthResult> verify2FA(String code) async {
    AppLogger.info('2FA verification started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API verify2fa', subCategory: 'auth');

      final verify2faResponse = await _runner
          .runValidatedTransform<dynamic, AuthResponse>(
            lane: ApiRequestLane.authTwoFactor,
            request: (extra) async {
              final (success, failure) = await api.rawApi
                  .getAuthenticationApi()
                  .verify2FA(
                    twoFactorAuthCode: TwoFactorAuthCode(code: code),
                    extra: extra,
                  )
                  .validateVrc();

              if (failure != null) {
                return (null, failure);
              }

              return _runner.runValidatedTransform<dynamic, AuthResponse>(
                lane: ApiRequestLane.authSession,
                request: (loginExtra) async {
                  final (userSuccess, userFailure) = await api.rawApi
                      .getAuthenticationApi()
                      .getCurrentUser(extra: loginExtra)
                      .validateVrc();
                  if (userSuccess != null) {
                    return (
                      ValidResponse(AuthResponse(), userSuccess.response),
                      null,
                    );
                  }
                  return (null, userFailure);
                },
              );
            },
          );

      final (success, failure) = verify2faResponse;

      if (failure != null) {
        final failureSummary = summarizeErrorForLog(failure);
        AppLogger.warning(
          '2FA verification rejected by API: $failureSummary',
          subCategory: 'auth',
        );
        return TwoFactorAuthResult(
          status: TwoFactorAuthResultStatus.failure,
          errorMessage: formatApiError('2FA verification failed', failure),
        );
      }

      AppLogger.debug(
        'API verify2fa call completed successfully',
        subCategory: 'auth',
      );

      final currentUser = verify2faResponse.$1?.response.data;
      if (currentUser != null) {
        AppLogger.info('2FA verification successful', subCategory: 'auth');
        return TwoFactorAuthResult(
          status: TwoFactorAuthResultStatus.success,
          currentUser: currentUser,
        );
      } else {
        AppLogger.error(
          'currentUser is null after successful verify2fa',
          subCategory: 'auth',
        );
        return TwoFactorAuthResult(
          status: TwoFactorAuthResultStatus.failure,
          errorMessage: '2FA verification failed: No user data received',
        );
      }
    } catch (e, s) {
      logAuthException('2FA verify', e, s);
      return TwoFactorAuthResult(
        status: TwoFactorAuthResultStatus.failure,
        errorMessage: formatApiError('2FA verification failed', e),
      );
    }
  }
}
