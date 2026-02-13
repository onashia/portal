import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/error_utils.dart';

void main() {
  group('formatApiError - Credential Errors', () {
    const expectedMessage = 'Invalid Username/Email or Password';
    const prefix = 'Login failed';

    final testCases = {
      'missing credentials',
      'invalid credentials',
      'invalid username',
      'invalid password',
      'invalid email',
      'authentication failed',
      'login failed',
    };

    for (final error in testCases) {
      test('maps "$error" → $expectedMessage', () {
        final result = formatApiError(prefix, error);
        expect(result, contains(expectedMessage));
      });
    }
  });

  group('formatApiError - 2FA Errors', () {
    const expectedMessage = 'Invalid 2FA Code';
    const prefix = '2FA verification failed';

    final testCases = {
      'invalid 2fa',
      'invalid 2fa code',
      'invalid code',
      'incorrect 2fa',
      'incorrect code',
      '2fa failed',
      'two-factor authentication',
      '2fa error',
    };

    for (final error in testCases) {
      test('maps "$error" → $expectedMessage', () {
        final result = formatApiError(prefix, error);
        expect(result, contains(expectedMessage));
      });
    }
  });

  group('formatApiError - Rate Limiting', () {
    const expectedMessage = 'Too many attempts, please try again later';
    const prefix = 'Login failed';

    final testCases = {'too many requests', '429 Too Many Requests'};

    for (final error in testCases) {
      test('maps "$error" → $expectedMessage', () {
        final result = formatApiError(prefix, error);
        expect(result, contains(expectedMessage));
      });
    }
  });

  group('formatApiError - Network Errors', () {
    const prefix = 'Login failed';

    final testCases = {
      'timeout': 'Connection timed out',
      'timed out': 'Connection timed out',
      'connection failed': 'Connection error',
      'network error': 'Connection error',
    };

    for (final entry in testCases.entries) {
      test('maps "${entry.key}" → ${entry.value}', () {
        final result = formatApiError(prefix, entry.key);
        expect(result, contains(entry.value));
      });
    }
  });

  group('formatApiError - Account Status', () {
    const expectedMessage = 'Account temporarily unavailable';
    const prefix = 'Login failed';

    final testCases = {'account locked', 'account suspended'};

    for (final error in testCases) {
      test('maps "$error" → $expectedMessage', () {
        final result = formatApiError(prefix, error);
        expect(result, contains(expectedMessage));
      });
    }
  });

  group('formatApiError - Email Verification', () {
    const expectedMessage = 'Email verification required';
    const prefix = 'Login failed';

    final testCases = {'check your email', 'verify your email'};

    for (final error in testCases) {
      test('maps "$error" → $expectedMessage', () {
        final result = formatApiError(prefix, error);
        expect(result, contains(expectedMessage));
      });
    }
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
      expect(result.length, lessThan(longError.length));
      expect(result.length, prefixLength + 50);
      expect(result, endsWith('...'));
    });

    test('returns full mapped message for short errors', () {
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

  group('formatUiErrorMessage', () {
    test('returns fallback for null', () {
      final result = formatUiErrorMessage(null);
      expect(result, 'Something went wrong. Please try again.');
    });

    test('returns fallback for instance-of style messages', () {
      final result = formatUiErrorMessage(Exception());
      expect(result, 'Something went wrong. Please try again.');
    });

    test('uses first line from multiline errors', () {
      final result = formatUiErrorMessage('Primary message\nMore details');
      expect(result, 'Primary message');
    });

    test('returns custom fallback when provided', () {
      final result = formatUiErrorMessage(
        null,
        fallbackMessage: 'Temporary issue',
      );
      expect(result, 'Temporary issue');
    });
  });
}
