// ignore: depend_on_referenced_packages
import 'package:dio_response_validator/dio_response_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/services/auth_service.dart';
import 'package:vrchat_dart/src/api/src/auth_api.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockVrchatDart extends Mock implements VrchatDart {}

class _MockAuthApi extends Mock implements AuthApi {}

dynamic _loginFailureResponse(String message, {int statusCode = 401}) {
  return (
    null,
    InvalidResponse(
      VrcError(message: message, statusCode: statusCode),
      StackTrace.empty,
    ),
  );
}

void main() {
  group('AuthService.login', () {
    late _MockVrchatDart mockApi;
    late _MockAuthApi mockAuthApi;
    late AuthService service;
    late List<String> loggedMessages;
    late DebugPrintCallback originalDebugPrint;

    setUp(() {
      mockApi = _MockVrchatDart();
      mockAuthApi = _MockAuthApi();
      service = AuthService(mockApi);
      loggedMessages = <String>[];
      originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          loggedMessages.add(message);
        }
      };

      when(() => mockApi.auth).thenReturn(mockAuthApi);
      when(() => mockAuthApi.currentUser).thenReturn(null);
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('logs a single-line failure summary when login is rejected', () async {
      when(
        () => mockAuthApi.login(username: 'alice', password: 'secret'),
      ).thenAnswer(
        (_) async => _loginFailureResponse(
          'Account banned\nfull backend payload should not be logged',
          statusCode: 403,
        ),
      );

      final result = await service.login('alice', 'secret');

      expect(result.status, AuthResultStatus.failure);
      final logged = loggedMessages.join('\n');
      expect(logged, contains('Login rejected by API: 403: Account banned'));
      expect(
        logged,
        isNot(contains('full backend payload should not be logged')),
      );
    });
  });
}
