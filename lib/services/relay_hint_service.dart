import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';
import '../models/relay_hint_message.dart';
import '../utils/app_logger.dart';
import 'relay_bootstrap_client.dart';
import 'relay_heartbeat_monitor.dart';
import 'relay_reconnect_scheduler.dart';

/// Injectable factory type for opening a [WebSocketChannel], used in tests
/// to substitute a fake in-memory channel.
typedef ChannelConnector = WebSocketChannel Function(Uri uri);

class RelayHintService {
  RelayHintService({
    RelayBootstrapClient? bootstrapClient,
    RelayHeartbeatMonitor? heartbeatMonitor,
    ReconnectScheduler? reconnectScheduler,
    ChannelConnector? channelConnector,
    DateTime Function()? now,
    math.Random? random,
    Dio? dio,
    String? bootstrapUrl,
    String? appSecret,
    Duration? heartbeatInterval,
    Duration? heartbeatStaleAfter,
  }) : _now = now ?? DateTime.now,
       _channelConnector = channelConnector ?? WebSocketChannel.connect {
    final effectiveDio = dio ?? Dio();
    effectiveDio.options.connectTimeout = Duration(
      seconds: AppConstants.relayBootstrapTimeoutSeconds,
    );
    effectiveDio.options.receiveTimeout = Duration(
      seconds: AppConstants.relayBootstrapTimeoutSeconds,
    );

    _bootstrapClient =
        bootstrapClient ??
        RelayBootstrapClient(
          dio: effectiveDio,
          bootstrapUrl: bootstrapUrl ?? AppConstants.relayBootstrapUrl,
          appSecret: appSecret ?? AppConstants.relayAppSecret,
        );

    final effectiveRandom = random ?? math.Random();
    _heartbeatMonitor =
        heartbeatMonitor ??
        RelayHeartbeatMonitor(
          interval: heartbeatInterval,
          staleAfter: heartbeatStaleAfter,
          now: now,
        );
    _reconnectScheduler =
        reconnectScheduler ??
        ReconnectScheduler(
          random: effectiveRandom,
          baseSeconds: AppConstants.relayReconnectBaseSeconds,
          maxSeconds: AppConstants.relayReconnectMaxSeconds,
        );
  }

  final DateTime Function() _now;
  final ChannelConnector _channelConnector;

  late final RelayBootstrapClient _bootstrapClient;
  late final RelayHeartbeatMonitor _heartbeatMonitor;
  late final ReconnectScheduler _reconnectScheduler;

  final StreamController<RelayHintMessage> _hintsController =
      StreamController<RelayHintMessage>.broadcast();
  final StreamController<RelayConnectionStatus> _statusController =
      StreamController<RelayConnectionStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;

  bool _isDisposed = false;
  bool _shouldStayConnected = false;
  bool _isConnecting = false;
  String? _targetGroupId;
  String? _targetClientId;
  DateTime? _runtimeDisabledUntil;

  Stream<RelayHintMessage> get hints => _hintsController.stream;
  Stream<RelayConnectionStatus> get statuses => _statusController.stream;

  bool get isConnected => _channel != null;

  /// True when this service has valid bootstrap configuration.
  bool get isConfigured => _bootstrapClient.isConfigured;

  DateTime? get runtimeDisabledUntil => _runtimeDisabledUntil;

  Future<void> connect({
    required String groupId,
    required String clientId,
  }) async {
    _targetGroupId = groupId;
    _targetClientId = clientId;
    _shouldStayConnected = true;

    if (!isConfigured) {
      _emitStatus(
        const RelayConnectionStatus(
          connected: false,
          error: 'relay_misconfigured',
        ),
      );
      return;
    }

    if (_runtimeDisabledUntil != null &&
        _runtimeDisabledUntil!.isAfter(_now())) {
      _emitStatus(
        RelayConnectionStatus(
          connected: false,
          error:
              'Relay temporarily disabled until ${_runtimeDisabledUntil!.toIso8601String()}',
        ),
      );
      return;
    }

    if (_isConnecting || _channel != null) {
      return;
    }

    _isConnecting = true;
    try {
      final wsUri = await _bootstrapClient.bootstrap(
        groupId: groupId,
        clientId: clientId,
        now: _now,
        onRuntimeDisabled: (until) {
          _runtimeDisabledUntil = until;
        },
      );

      if (!_shouldStayConnected || _isDisposed) {
        return;
      }

      final channel = _channelConnector(wsUri);
      _channel = channel;

      try {
        await channel.ready;
      } catch (e) {
        _emitStatus(
          RelayConnectionStatus(
            connected: false,
            error: 'Relay handshake failed: $e',
          ),
        );
        _handleDisconnect();
        return;
      }

      if (!_shouldStayConnected || _isDisposed) {
        return;
      }

      _reconnectScheduler.reset();
      _runtimeDisabledUntil = null;
      _emitStatus(const RelayConnectionStatus(connected: true));

      _channelSubscription = channel.stream.listen(
        _handleRawMessage,
        onError: (error, stackTrace) {
          AppLogger.warning(
            'Relay websocket error: $error',
            subCategory: 'relay',
          );
          _emitStatus(
            const RelayConnectionStatus(
              connected: false,
              error: 'Relay connection error',
            ),
          );
          _handleDisconnect();
        },
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      _heartbeatMonitor.start(
        sendPing: (now) =>
            _send({'type': 'ping', 'ts': now.millisecondsSinceEpoch}),
        onStale: () {
          AppLogger.warning(
            'Relay heartbeat stale; reconnecting websocket',
            subCategory: 'relay',
          );
          _handleDisconnect();
        },
      );
    } catch (e, s) {
      AppLogger.warning('Relay connect failed: $e', subCategory: 'relay');
      AppLogger.debug('$s', subCategory: 'relay');
      final detail = e is DioException && e.response?.statusCode != null
          ? ' (${e.response!.statusCode})'
          : '';
      _emitStatus(
        RelayConnectionStatus(
          connected: false,
          error: 'Relay connect failed$detail',
        ),
      );
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _shouldStayConnected = false;
    _reconnectScheduler.cancel();
    await _closeChannel();
    _emitStatus(const RelayConnectionStatus(connected: false));
  }

  Future<void> publishHint(RelayHintMessage hint) async {
    if (_channel == null || !_shouldStayConnected) {
      return;
    }
    // Encode once so we can enforce the Relay Protocol Contract documented in
    // workers/relay_assist/README.md before writing to the websocket.
    final encoded = jsonEncode({
      'type': 'publish_hint',
      'payload': hint.toJson(),
    });
    if (encoded.length > AppConstants.relayMaxOutboundPayloadBytes) {
      AppLogger.warning(
        'Relay: skipped publish_hint — payload too large '
        '(${encoded.length} > ${AppConstants.relayMaxOutboundPayloadBytes} bytes)',
        subCategory: 'relay',
      );
      return;
    }
    _channel?.sink.add(encoded);
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await disconnect();
    await _hintsController.close();
    await _statusController.close();
  }

  void _handleRawMessage(dynamic event) {
    if (event is! String) {
      AppLogger.debug(
        'Relay: dropped binary frame (${event.runtimeType})',
        subCategory: 'relay',
      );
      return;
    }
    if (event.length > AppConstants.relayMaxInboundMessageBytes) {
      AppLogger.debug(
        'Relay: dropped oversized message (${event.length} bytes)',
        subCategory: 'relay',
      );
      return;
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map<String, dynamic>) {
        AppLogger.debug(
          'Relay: dropped non-object JSON (${decoded.runtimeType})',
          subCategory: 'relay',
        );
        return;
      }
      payload = decoded;
    } catch (_) {
      AppLogger.debug('Relay: dropped non-JSON message', subCategory: 'relay');
      return;
    }

    final type = payload['type']?.toString();
    if (type == 'pong') {
      _heartbeatMonitor.recordPong();
      return;
    }

    if (type == 'hint') {
      final rawHint = payload['payload'];
      if (rawHint is! Map<String, dynamic>) {
        AppLogger.debug(
          'Relay: dropped hint with non-map payload',
          subCategory: 'relay',
        );
        return;
      }
      final hint = RelayHintMessage.fromJson(rawHint);
      if (!hint.isStructurallyValid) {
        AppLogger.debug(
          'Relay: dropped structurally invalid hint (hintId=${hint.hintId})',
          subCategory: 'relay',
        );
        return;
      }
      if (hint.isExpired()) {
        AppLogger.debug(
          'Relay: dropped expired hint (expiresAt=${hint.expiresAt.toIso8601String()})',
          subCategory: 'relay',
        );
        return;
      }
      _hintsController.add(hint);
      return;
    }

    if (type == 'error') {
      final message = payload['message']?.toString() ?? 'Relay error';
      _emitStatus(RelayConnectionStatus(connected: false, error: message));
      return;
    }

    if (type == 'disabled') {
      final retryAfterSeconds =
          ((payload['retryAfterSeconds'] as num?)?.toInt() ??
                  AppConstants.relayCircuitBreakerCooldownSeconds)
              .clamp(0, AppConstants.relayMaxRetryAfterSeconds);
      _runtimeDisabledUntil = _now().add(Duration(seconds: retryAfterSeconds));
      _emitStatus(
        const RelayConnectionStatus(
          connected: false,
          error: 'Relay temporarily disabled by server',
        ),
      );
      unawaited(disconnect());
    }
  }

  void _handleDisconnect() {
    if (_channel == null) {
      return;
    }
    unawaited(_closeChannel());
    _emitStatus(const RelayConnectionStatus(connected: false));
    _scheduleReconnect();
  }

  Future<void> _closeChannel() async {
    _heartbeatMonitor.stop();
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _scheduleReconnect() {
    if (!_shouldStayConnected || _isDisposed) {
      return;
    }
    if (_targetGroupId == null || _targetClientId == null) {
      return;
    }
    if (_runtimeDisabledUntil != null &&
        _runtimeDisabledUntil!.isAfter(_now())) {
      return;
    }

    _reconnectScheduler.schedule(() {
      if (_isDisposed || !_shouldStayConnected) {
        return;
      }
      unawaited(connect(groupId: _targetGroupId!, clientId: _targetClientId!));
    });
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (e) {
      AppLogger.warning('Relay send failed: $e', subCategory: 'relay');
    }
  }

  void _emitStatus(RelayConnectionStatus status) {
    if (_isDisposed || _statusController.isClosed) {
      return;
    }
    _statusController.add(status);
  }

  // ---------------------------------------------------------------------------
  // Static helpers.
  // ---------------------------------------------------------------------------

  @visibleForTesting
  static bool isHeartbeatStale({
    required DateTime now,
    required DateTime? lastInboundAt,
    required Duration staleAfter,
  }) {
    if (lastInboundAt == null) {
      return true;
    }
    return !lastInboundAt.add(staleAfter).isAfter(now);
  }
}
