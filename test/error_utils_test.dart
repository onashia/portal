import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/error_utils.dart';

void main() {
  group('formatApiError - Credential Errors', () {
    test('maps "missing credentials" → Invalid Username/Email or Password', () {
      final result = formatApiError('Login failed', 'missing credentials');
      expect(result, contains('Invalid Username/Email or Password'));
    });

    test('maps "invalid credentials" → Invalid Username/Email or Password', () {
      final result = formatApiError('Login failed', 'invalid credentials');
      expect(result, contains('Invalid Username/Email or Password'));
    });

    test('maps "invalid username" → Invalid Username/Email or Password', () {
      final result = formatApiError('Login failed', 'invalid username');
      expect(result, contains('Invalid Username/Email or Password'));
    });

    test('maps "invalid password" → Invalid Username/Email or Password', () {
      final result = formatApiError('Login failed', 'invalid password');
      expect(result, contains('Invalid Username/Email or Password'));
    });

    test('maps "invalid email" → Invalid Username/Email or Password', () {
      final result = formatApiError('Login failed', 'invalid email');
      expect(result, contains('Invalid Username/Email or Password'));
    });

    test(
      'maps "authentication failed" → Invalid Username/Email or Password',
      () {
        final result = formatApiError('Login failed', 'authentication failed');
        expect(result, contains('Invalid Username/Email or Password'));
      },
    );

    test('maps "login failed" → Invalid Username/Email or Password', () {
      final result = formatApiError('Login failed', 'login failed');
      expect(result, contains('Invalid Username/Email or Password'));
    });
  });

  group('formatApiError - 2FA Errors', () {
    test('maps "invalid 2fa" → Invalid 2FA Code', () {
      final result = formatApiError('2FA verification failed', 'invalid 2fa');
      expect(result, contains('Invalid 2FA Code'));
    });

    test('maps "invalid 2fa code" → Invalid 2FA Code', () {
      final result = formatApiError(
        '2FA verification failed',
        'invalid 2fa code',
      );
      expect(result, contains('Invalid 2FA Code'));
    });

    test('maps "invalid code" → Invalid 2FA Code', () {
      final result = formatApiError('2FA verification failed', 'invalid code');
      expect(result, contains('Invalid 2FA Code'));
    });

    test('maps "incorrect 2fa" → Invalid 2FA Code', () {
      final result = formatApiError('2FA verification failed', 'incorrect 2fa');
      expect(result, contains('Invalid 2FA Code'));
    });

    test('maps "incorrect code" → Invalid 2FA Code', () {
      final result = formatApiError(
        '2FA verification failed',
        'incorrect code',
      );
      expect(result, contains('Invalid 2FA Code'));
    });

    test('maps "2fa failed" → Invalid 2FA Code', () {
      final result = formatApiError('2FA verification failed', '2fa failed');
      expect(result, contains('Invalid 2FA Code'));
    });

    test('maps "two-factor authentication" → Invalid 2FA Code', () {
      final result = formatApiError(
        '2FA verification failed',
        'two-factor authentication',
      );
      expect(result, contains('Invalid 2FA Code'));
    });

    test('maps "2fa error" → Invalid 2FA Code', () {
      final result = formatApiError('2FA verification failed', '2fa error');
      expect(result, contains('Invalid 2FA Code'));
    });
  });

  group('formatApiError - Rate Limiting', () {
    test(
      'maps "too many requests" → Too many attempts, please try again later',
      () {
        final result = formatApiError('Login failed', 'too many requests');
        expect(result, contains('Too many attempts, please try again later'));
      },
    );

    test('maps "429" → Too many attempts, please try again later', () {
      final result = formatApiError('Login failed', '429 Too Many Requests');
      expect(result, contains('Too many attempts, please try again later'));
    });
  });

  group('formatApiError - Network Errors', () {
    test('maps "timeout" → Connection timed out', () {
      final result = formatApiError('Login failed', 'timeout');
      expect(result, contains('Connection timed out'));
    });

    test('maps "timed out" → Connection timed out', () {
      final result = formatApiError('Login failed', 'timed out');
      expect(result, contains('Connection timed out'));
    });

    test('maps "network" → Connection error', () {
      final result = formatApiError('Login failed', 'network error');
      expect(result, contains('Connection error'));
    });

    test('maps "connection" → Connection error', () {
      final result = formatApiError('Login failed', 'connection failed');
      expect(result, contains('Connection error'));
    });

    test('maps "network error" → Connection error', () {
      final result = formatApiError('Login failed', 'network error');
      expect(result, contains('Connection error'));
    });
  });

  group('formatApiError - Account Status', () {
    test('maps "account locked" → Account temporarily unavailable', () {
      final result = formatApiError('Login failed', 'account locked');
      expect(result, contains('Account temporarily unavailable'));
    });

    test('maps "account suspended" → Account temporarily unavailable', () {
      final result = formatApiError('Login failed', 'account suspended');
      expect(result, contains('Account temporarily unavailable'));
    });
  });

  group('formatApiError - Email Verification', () {
    test('maps "check your email" → Email verification required', () {
      final result = formatApiError('Login failed', 'check your email');
      expect(result, contains('Email verification required'));
    });

    test('maps "verify your email" → Email verification required', () {
      final result = formatApiError('Login failed', 'verify your email');
      expect(result, contains('Email verification required'));
    });
  });

  group('formatApiError - Case Insensitive', () {
    test('matches uppercase MISSING CREDENTIALS', () {
      final result = formatApiError('Login failed', 'MISSING CREDENTIALS');
      expect(result, contains('Invalid Username/Email or Password'));
    });

    test('matches MixedCase NetworkError', () {
      final result = formatApiError('Login failed', 'NetworkError');
      expect(result, contains('Connection error'));
    });

    test('matches lowercase "2fa error"', () {
      final result = formatApiError('2FA verification failed', '2fa error');
      expect(result, contains('Invalid 2FA Code'));
    });
  });

  group('formatApiError - Edge Cases', () {
    test('truncates long error messages (>50 chars)', () {
      final longError =
          'This is a very long error message that exceeds fifty characters and should be truncated';
      final result = formatApiError('Login failed', longError);
      final prefixLength = 'Login failed: '.length;
      expect(result.length, greaterThan(50));
      expect(result.length, lessThan(47 + prefixLength + 4));
      expect(result, endsWith('...'));
    });

    test('returns full message for short errors (≤50 chars)', () {
      final shortError = 'Invalid credentials';
      final result = formatApiError('Login failed', shortError);
      expect(
        result,
        equals('Login failed: Invalid Username/Email or Password'),
      );
    });

    test('handles multiline errors (extracts first line)', () {
      final multilineError = '''Invalid username
Additional debug info
More details''';
      final result = formatApiError('Login failed', multilineError);
      expect(
        result,
        contains('Login failed: Invalid Username/Email or Password'),
      );
      expect(result, isNot(contains('Additional debug info')));
    });

    test('handles unmapped error patterns', () {
      final unmappedError = 'Unknown error occurred';
      final result = formatApiError('Operation failed', unmappedError);
      expect(result, contains('Operation failed'));
      expect(result, contains('Unknown error occurred'));
    });

    test('handles error object with toString()', () {
      final errorObject = Exception('Custom exception message');
      final result = formatApiError('Operation failed', errorObject);
      expect(result, contains('Operation failed'));
      expect(result, contains('Custom exception message'));
    });
  });
}
