import 'package:vrchat_dart/vrchat_dart.dart';
import '../utils/app_logger.dart';
import '../utils/dio_error_logger.dart';
import '../utils/error_utils.dart';

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

  TwoFactorAuthService(this.api);

  Future<TwoFactorAuthResult> verify2FA(String code) async {
    AppLogger.info('2FA verification started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API verify2fa', subCategory: 'auth');

      final verify2faResponse = await api.auth.verify2fa(code);

      final (success, failure) = verify2faResponse;

      if (failure != null) {
        AppLogger.warning(
          '2FA verification rejected by API',
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

      final currentUser = api.auth.currentUser;
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
