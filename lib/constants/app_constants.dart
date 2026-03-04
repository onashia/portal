class AppConstants {
  static const int maxBackoffDelay = 300;
  static const int pollingIntervalSeconds = 120;
  static const int pollingJitterSeconds = 10;
  static const bool relayAssistEnabled = bool.fromEnvironment(
    'PORTAL_RELAY_ASSIST_ENABLED',
    defaultValue: true,
  );
  static const String relayBootstrapUrl = String.fromEnvironment(
    'PORTAL_RELAY_BOOTSTRAP_URL',
    defaultValue:
        'https://portal-relay-assist.me-3aa.workers.dev/relay/bootstrap',
  );
  static const int relayBootstrapTimeoutSeconds = 8;
  static const int relayHintTtlSeconds = 45;
  static const int relayHintDedupeSeconds = 60;
  static const int relayPublishDedupeSeconds = 30;
  static const int relayReconnectBaseSeconds = 2;
  static const int relayReconnectMaxSeconds = 20;
  static const int relayCircuitBreakerThreshold = 4;
  static const int relayCircuitBreakerCooldownSeconds = 60;
  static const int relayInviteRetryWindowSeconds = 25;
  static const int vrchatApiConnectTimeoutSeconds = 10;
  static const int vrchatApiReceiveTimeoutSeconds = 20;
  static const int groupInstancesRequestTimeoutSeconds = 20;
  static const int groupInstancesMaxConcurrentRequests = 4;
  static const int boostPollingIntervalSeconds = 10;
  static const int boostPollingJitterSeconds = 2;
  static const int boostDurationMinutes = 15;
  static const int maxAvatarCacheSize = 100;
  static const int maxAvatarMemoryCacheBytes = 33554432;
  static const int maxAvatarMemoryEntryBytes = 2097152;
  static const int imageDiskCacheMaxEntries = 400;
  static const int imageDiskCacheTtlDays = 30;
  static const int imageCachePruneIntervalHours = 12;
  static const int imageFailureCacheTtlMinutes = 2;
  static const int vrchatStatusPollingIntervalSeconds = 300;
  static const int vrchatStatusPollingJitterSeconds = 60;
  static const Duration selectionRefreshDebounceDuration = Duration(
    milliseconds: 500,
  );
}
