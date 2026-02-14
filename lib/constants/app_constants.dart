class AppConstants {
  static const int maxBackoffDelay = 300;
  static const int pollingIntervalSeconds = 120;
  static const int pollingJitterSeconds = 10;
  static const int vrchatApiConnectTimeoutSeconds = 10;
  static const int vrchatApiReceiveTimeoutSeconds = 20;
  static const int groupInstancesRequestTimeoutSeconds = 20;
  static const int groupInstancesMaxConcurrentRequests = 4;
  static const int boostPollingIntervalSeconds = 10;
  static const int boostPollingJitterSeconds = 2;
  static const int boostDurationMinutes = 15;
  static const int maxAvatarCacheSize = 100;
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
