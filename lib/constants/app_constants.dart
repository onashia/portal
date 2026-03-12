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
  // The app secret is a compile-time constant embedded in the client binary.
  // It is a defense-in-depth measure — not a true authentication boundary —
  // because a determined actor can extract it via reverse engineering.
  // The real enforcement is server-side rate limiting (BootstrapRateLimiter).
  static const String relayAppSecret = String.fromEnvironment(
    'PORTAL_RELAY_APP_SECRET',
    defaultValue: '',
  );
  // Development-only escape hatch for local relay testing without TLS.
  // Keep disabled in normal environments so the client refuses plaintext
  // bootstrap and websocket transports.
  static const bool allowInsecureRelayTransport = bool.fromEnvironment(
    'PORTAL_ALLOW_INSECURE_RELAY_TRANSPORT',
    defaultValue: false,
  );
  static const int relayBootstrapTimeoutSeconds = 8;
  static const int relayHintTtlSeconds = 45;
  static const int relayHintDedupeSeconds = 60;
  static const int relayPublishDedupeSeconds = 30;
  static const int relayHeartbeatIntervalSeconds = 20;
  static const int relayHeartbeatStaleSeconds = 60;
  static const int relayReconnectBaseSeconds = 2;
  static const int relayReconnectMaxSeconds = 20;
  static const int relayCircuitBreakerThreshold = 4;
  static const int relayCircuitBreakerCooldownSeconds = 60;
  static const int relayMaxRetryAfterSeconds = 3600;

  /// Maximum byte length accepted from the server on the relay WebSocket.
  /// Server-sent messages (hint, pong, error, ack, disabled) are well below
  /// this in practice; this is a safety guard against rogue/malformed frames.
  static const int relayMaxInboundMessageBytes = 8192;

  /// Maximum byte length the server accepts from the client on the relay
  /// WebSocket. Mirrors MAX_PAYLOAD_BYTES in workers/relay_assist/src/index.js.
  /// Keep in sync if the worker value changes.
  static const int relayMaxOutboundPayloadBytes = 2048;
  static const int relayInviteRetryWindowSeconds = 25;
  static const int vrchatApiConnectTimeoutSeconds = 10;
  static const int vrchatApiReceiveTimeoutSeconds = 20;
  static const int groupInstancesRequestTimeoutSeconds = 20;
  static const int groupInstancesMaxConcurrentRequests = 4;
  static const int groupInstanceEnrichmentTtlSeconds = 30;
  static const int groupInstanceEnrichmentFailureCooldownSeconds = 10;
  static const int groupInstanceEnrichmentLogDedupeSeconds = 30;
  static const int groupInstanceInviteVerificationMaxCandidates = 3;
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
