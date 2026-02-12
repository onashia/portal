/// Shared storage keys for SharedPreferences
class StorageKeys {
  StorageKeys._();

  /// Theme mode preference key
  static const String themeMode = 'theme_mode';

  /// Selected group IDs key
  static const String selectedGroupIds = 'selectedGroupIds';

  /// Auto-invite setting for new group instances
  static const String autoInviteEnabled = 'autoInviteEnabled';

  /// Boosted group ID for high-frequency polling
  static const String boostedGroupId = 'boostedGroupId';

  /// Boosted group expiration timestamp (ISO-8601)
  static const String boostExpiresAt = 'boostExpiresAt';
}
