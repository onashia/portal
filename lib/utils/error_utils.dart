/// Formats VRChat API errors into user-friendly messages.
///
/// Handles verbose API responses by extracting first line and mapping known
/// error patterns to simple, actionable messages. Works with any VRChat
/// API error (authentication, groups, calendar, invites, etc.).
///
/// Parameters:
/// - [prefix]: Context prefix (e.g., "Login failed", "2FA verification failed")
/// - [error]: The error object from API or exception
///
/// Returns: Formatted error message string
String formatApiError(String prefix, dynamic error) {
  var message = error.toString().split('\n').first.trim();
  final lowerMessage = message.toLowerCase();

  final Map<String, String> errorMappings = {
    'missing credentials': 'Invalid Username/Email or Password',
    'invalid credentials': 'Invalid Username/Email or Password',
    'invalid username': 'Invalid Username/Email or Password',
    'invalid password': 'Invalid Username/Email or Password',
    'invalid email': 'Invalid Username/Email or Password',
    'authentication failed': 'Invalid Username/Email or Password',
    'login failed': 'Invalid Username/Email or Password',
    'invalid 2fa': 'Invalid 2FA Code',
    'invalid 2fa code': 'Invalid 2FA Code',
    'invalid code': 'Invalid 2FA Code',
    'incorrect 2fa': 'Invalid 2FA Code',
    'incorrect code': 'Invalid 2FA Code',
    '2fa failed': 'Invalid 2FA Code',
    'two-factor authentication': 'Invalid 2FA Code',
    '2fa error': 'Invalid 2FA Code',
    'too many requests': 'Too many attempts, please try again later',
    '429': 'Too many attempts, please try again later',
    'timeout': 'Connection timed out',
    'timed out': 'Connection timed out',
    'network': 'Connection error',
    'connection': 'Connection error',
    'network error': 'Connection error',
    'account locked': 'Account temporarily unavailable',
    'account suspended': 'Account temporarily unavailable',
    'check your email': 'Email verification required',
    'verify your email': 'Email verification required',
  };

  for (final entry in errorMappings.entries) {
    if (lowerMessage.contains(entry.key)) {
      return '$prefix: ${entry.value}';
    }
  }

  if (message.length > 50) {
    return '$prefix: ${message.substring(0, 47)}...';
  }

  return '$prefix: $message';
}
