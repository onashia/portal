// ignore: depend_on_referenced_packages
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/services/two_factor_auth_service.dart';
import 'package:vrchat_dart/src/api/src/auth_api.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockAuthApi extends Mock implements AuthApi {}

dynamic _verifyFailureResponse(String message, {int statusCode = 401}) {
  return (
    null,
    InvalidResponse(
      VrcError(message: message, statusCode: statusCode),
      StackTrace.empty,
    ),
  );
}

void main() {
  group('TwoFactorAuthService.verify2FA', () {
    late _MockVrchatDart mockApi;
    late _MockAuthApi mockAuthApi;
    late TwoFactorAuthService service;
    late List<String> loggedMessages;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      mockApi = _MockVrchatDart();
      mockAuthApi = _MockAuthApi();
      service = TwoFactorAuthService(mockApi);
      loggedMessages = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          loggedMessages.add(message);
        }
      };

      when(() => mockApi.auth).thenReturn(mockAuthApi);
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('logs a single-line failure summary when 2FA is rejected', () async {
      when(() => mockAuthApi.verify2fa('123456')).thenAnswer(
        (_) async => _verifyFailureResponse(
          'Invalid 2FA code\nraw backend detail should not be logged',
        ),
      );

      final result = await service.verify2FA('123456');

      expect(result.status, TwoFactorAuthResultStatus.failure);
      final logged = loggedMessages.join('\n');
      expect(
        logged,
        contains('2FA verification rejected by API: 401: Invalid 2FA code'),
      );
      expect(
        logged,
        isNot(contains('raw backend detail should not be logged')),
      );
    });
  });
}
