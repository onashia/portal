import 'package:dio/dio.dart';

import '../constants/app_constants.dart';

/// Handles the HTTP bootstrap exchange that issues a short-lived WebSocket URI.
///
/// Clients POST their [groupId] and [clientId] to the relay bootstrap endpoint.
/// On success the server returns a signed [Uri] containing a short-lived token
/// in the query string (a trade-off required by the WebSocket API, which does
/// not support custom request headers during the upgrade handshake).
class RelayBootstrapClient {
  RelayBootstrapClient({
    required Dio dio,
    required String bootstrapUrl,
    required String appSecret,
  }) : _dio = dio,
       _bootstrapUrl = bootstrapUrl,
       _appSecret = appSecret;

  final Dio _dio;
  final String _bootstrapUrl;
  final String _appSecret;

  /// True when this client has the configuration required to make bootstrap
  /// requests. Returns false when [appSecret] or [bootstrapUrl] is empty, or
  /// when the relay feature flag is disabled at compile time.
  bool get isConfigured =>
      AppConstants.relayAssistEnabled &&
      _bootstrapUrl.trim().isNotEmpty &&
      _appSecret.isNotEmpty;

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
    final response = await _dio.post<dynamic>(
      _bootstrapUrl,
      data: {'groupId': groupId, 'clientId': clientId, 'version': '1'},
      options: Options(
        headers: {
          'content-type': 'application/json',
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
          (data['retryAfterSeconds'] as num?)?.toInt() ??
          AppConstants.relayCircuitBreakerCooldownSeconds;
      onRuntimeDisabled(now().add(Duration(seconds: retryAfterSeconds)));
      throw StateError('Relay runtime disabled by server');
    }

    final wsUrlString = data['wsUrl']?.toString();
    if (wsUrlString == null || wsUrlString.isEmpty) {
      throw StateError('Missing wsUrl from relay bootstrap');
    }
    return Uri.parse(wsUrlString);
  }
}
