import 'package:dio/dio.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../utils/app_logger.dart';

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

  void _logDioException(String context, Object error) {
    if (error is DioException) {
      final response = error.response;
      AppLogger.error(
        '$context DioException',
        subCategory: 'auth',
        error: {
          'type': error.type.toString(),
          'message': error.message,
          'uri': error.requestOptions.uri.toString(),
          'statusCode': response?.statusCode,
        },
      );
      if (response?.data != null) {
        AppLogger.debug(
          '$context Dio response data: ${response?.data}',
          subCategory: 'auth',
        );
      }
    }
  }

  Future<TwoFactorAuthResult> verify2FA(String code) async {
    AppLogger.info('2FA verification started', subCategory: 'auth');

    try {
      AppLogger.debug('Calling VRChat API verify2fa', subCategory: 'auth');

      final verify2faResponse = await api.auth.verify2fa(code);

      final (success, failure) = verify2faResponse;

      if (failure != null) {
        AppLogger.error('2FA verification failed', subCategory: 'auth');
        return TwoFactorAuthResult(
          status: TwoFactorAuthResultStatus.failure,
          errorMessage: '2FA verification failed: ${failure.toString()}',
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
      _logDioException('2FA verify', e);
      AppLogger.error(
        '2FA verification failed with exception',
        subCategory: 'auth',
        error: e,
        stackTrace: s,
      );
      return TwoFactorAuthResult(
        status: TwoFactorAuthResultStatus.failure,
        errorMessage: '2FA verification failed: ${e.toString()}',
      );
    }
  }
}
