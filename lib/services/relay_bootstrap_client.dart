import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../utils/app_logger.dart';

/// Handles the HTTP bootstrap exchange that issues a short-lived WebSocket URI.
///
/// Clients POST their [groupId] and [clientId] to the relay bootstrap endpoint.
/// On success the server returns a signed [Uri] containing a short-lived token
/// in the query string (a trade-off required by the WebSocket API, which does
/// not support custom request headers during the upgrade handshake). The token
/// TTL ([AppConstants.relayBootstrapTimeoutSeconds]) limits exposure if the URI
/// appears in logs.
class RelayBootstrapClient {
  RelayBootstrapClient({
    required Dio dio,
    required String bootstrapUrl,
    required String appSecret,
    bool allowInsecureTransport = AppConstants.allowInsecureRelayTransport,
  }) : _dio = dio,
       _bootstrapUrl = bootstrapUrl,
       _appSecret = appSecret,
       _allowInsecureTransport = allowInsecureTransport;

  final Dio _dio;
  final String _bootstrapUrl;
  final String _appSecret;
  final bool _allowInsecureTransport;

  /// True when this client has the configuration required to make bootstrap
  /// requests. Returns false when [appSecret] or [bootstrapUrl] is empty, or
  /// when the relay feature flag is disabled at compile time.
  bool get isConfigured =>
      AppConstants.relayAssistEnabled &&
      _appSecret.isNotEmpty &&
      _hasAllowedBootstrapUrl;

  bool get _hasAllowedBootstrapUrl {
    final uri = Uri.tryParse(_bootstrapUrl.trim());
    return uri != null &&
        uri.hasScheme &&
        uri.host.isNotEmpty &&
        _isAllowedBootstrapScheme(uri.scheme);
  }

  bool _isAllowedBootstrapScheme(String scheme) {
    return scheme == 'https' || (_allowInsecureTransport && scheme == 'http');
  }

  bool _isAllowedWebSocketScheme(String scheme) {
    return scheme == 'wss' || (_allowInsecureTransport && scheme == 'ws');
  }

  /// Requests a WebSocket URI from the relay bootstrap endpoint.
  ///
  /// Throws [StateError] when the server disables relay or returns an
  /// unexpected payload. Throws [DioException] for HTTP-level failures.
  ///
  /// The returned [Uri] contains a short-lived authentication token as a
  /// query parameter and must be used before [AppConstants.relayBootstrapTimeoutSeconds]
  /// has elapsed.
  Future<Uri> bootstrap({
    required String groupId,
    required String clientId,
    required DateTime Function() now,
    required void Function(DateTime disabledUntil) onRuntimeDisabled,
  }) async {
    if (!_hasAllowedBootstrapUrl) {
      throw StateError(
        'Relay bootstrap requires HTTPS unless insecure relay transport is enabled',
      );
    }
    final bootstrapUri = Uri.parse(_bootstrapUrl.trim());
    if (_allowInsecureTransport && bootstrapUri.scheme == 'http') {
      AppLogger.warning(
        'Relay bootstrap is using insecure HTTP transport; only enable this for local development',
        subCategory: 'relay',
      );
    }

    final response = await _dio.post<dynamic>(
      bootstrapUri.toString(),
      data: {'groupId': groupId, 'clientId': clientId, 'version': '1'},
      options: Options(
        headers: {
          'content-type': 'application/json',
          // Defense-in-depth: the secret is embedded in the binary and can be
          // reverse-engineered. Server-side rate limiting is the real barrier.
          'x-app-secret': _appSecret,
        },
      ),
    );

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Invalid relay bootstrap response payload');
    }

    final relayEnabled = data['relayEnabled'] != false;
    if (!relayEnabled) {
      final retryAfterSeconds =
          ((data['retryAfterSeconds'] as num?)?.toInt() ??
                  AppConstants.relayCircuitBreakerCooldownSeconds)
              .clamp(0, AppConstants.relayMaxRetryAfterSeconds);
      onRuntimeDisabled(now().add(Duration(seconds: retryAfterSeconds)));
      throw StateError('Relay runtime disabled by server');
    }

    final wsUrlString = data['wsUrl']?.toString();
    if (wsUrlString == null || wsUrlString.isEmpty) {
      throw StateError('Missing wsUrl from relay bootstrap');
    }
    final uri = Uri.parse(wsUrlString);
    if (!_isAllowedWebSocketScheme(uri.scheme)) {
      throw StateError(
        'Relay bootstrap returned an insecure WebSocket URI scheme: ${uri.scheme}',
      );
    }
    if (_allowInsecureTransport && uri.scheme == 'ws') {
      AppLogger.warning(
        'Relay bootstrap returned an insecure WebSocket transport; only enable this for local development',
        subCategory: 'relay',
      );
    }
    return uri;
  }
}
