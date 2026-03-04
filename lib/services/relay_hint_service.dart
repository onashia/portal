import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/app_constants.dart';
import '../models/relay_hint_message.dart';
import '../utils/app_logger.dart';

typedef RelayBootstrapResolver =
    Future<String> Function({
      required String groupId,
      required String userId,
      required String clientId,
    });

class RelayHintService {
  RelayHintService({
    Dio? dio,
    String? bootstrapUrl,
    math.Random? random,
    DateTime Function()? now,
    Duration? heartbeatInterval,
    Duration? heartbeatStaleAfter,
    WebSocketChannel Function(Uri uri)? channelConnector,
    RelayBootstrapResolver? bootstrapResolver,
  }) : _dio = dio ?? Dio(),
       _bootstrapUrl = bootstrapUrl ?? AppConstants.relayBootstrapUrl,
       _random = random ?? math.Random(),
       _now = now ?? DateTime.now,
       _heartbeatInterval =
           heartbeatInterval ??
           const Duration(seconds: AppConstants.relayHeartbeatIntervalSeconds),
       _heartbeatStaleAfter =
           heartbeatStaleAfter ??
           const Duration(seconds: AppConstants.relayHeartbeatStaleSeconds),
       _channelConnector = channelConnector ?? WebSocketChannel.connect,
       _bootstrapResolver = bootstrapResolver {
    _dio.options.connectTimeout = Duration(
      seconds: AppConstants.relayBootstrapTimeoutSeconds,
    );
    _dio.options.receiveTimeout = Duration(
      seconds: AppConstants.relayBootstrapTimeoutSeconds,
    );
  }

  final Dio _dio;
  final String _bootstrapUrl;
  final math.Random _random;
  final DateTime Function() _now;
  final Duration _heartbeatInterval;
  final Duration _heartbeatStaleAfter;
  final WebSocketChannel Function(Uri uri) _channelConnector;
  final RelayBootstrapResolver? _bootstrapResolver;
  final StreamController<RelayHintMessage> _hintsController =
      StreamController<RelayHintMessage>.broadcast();
  final StreamController<RelayConnectionStatus> _statusController =
      StreamController<RelayConnectionStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  bool _isDisposed = false;
  bool _shouldStayConnected = false;
  bool _isConnecting = false;
  String? _targetGroupId;
  String? _targetUserId;
  String? _targetClientId;
  DateTime? _runtimeDisabledUntil;
  DateTime? _lastInboundAt;
  DateTime? _lastPongAt;
  int _reconnectAttempt = 0;

  Stream<RelayHintMessage> get hints => _hintsController.stream;
  Stream<RelayConnectionStatus> get statuses => _statusController.stream;

  bool get isConnected => _channel != null;

  bool get isConfigured =>
      AppConstants.relayAssistEnabled && _bootstrapUrl.trim().isNotEmpty;

  DateTime? get runtimeDisabledUntil => _runtimeDisabledUntil;

  Future<void> connect({
    required String groupId,
    required String userId,
    required String clientId,
  }) async {
    _targetGroupId = groupId;
    _targetUserId = userId;
    _targetClientId = clientId;
    _shouldStayConnected = true;

    if (!isConfigured) {
      _emitStatus(
        RelayConnectionStatus(
          connected: false,
          error: 'Relay unavailable: missing bootstrap configuration',
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
      final bootstrap = _bootstrapResolver ?? _bootstrap;
      final wsUrl = await bootstrap(
        groupId: groupId,
        userId: userId,
        clientId: clientId,
      );
      if (!_shouldStayConnected || _isDisposed) {
        return;
      }

      final channel = _channelConnector(Uri.parse(wsUrl));
      _channel = channel;
      _reconnectAttempt = 0;
      _lastInboundAt = _now();
      _lastPongAt = _lastInboundAt;
      _emitStatus(const RelayConnectionStatus(connected: true));

      _channelSubscription = channel.stream.listen(
        _handleRawMessage,
        onError: (error, stackTrace) {
          AppLogger.warning(
            'Relay websocket error: $error',
            subCategory: 'relay',
          );
          _emitStatus(
            RelayConnectionStatus(
              connected: false,
              error: 'Relay connection error',
            ),
          );
          _handleDisconnect();
        },
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
        final now = _now();
        if (isHeartbeatStale(
          now: now,
          lastInboundAt: _lastPongAt,
          staleAfter: _heartbeatStaleAfter,
        )) {
          AppLogger.warning(
            'Relay heartbeat stale; reconnecting websocket',
            subCategory: 'relay',
          );
          _heartbeatTimer?.cancel();
          _heartbeatTimer = null;
          _handleDisconnect();
          return;
        }
        _send({'type': 'ping', 'ts': now.millisecondsSinceEpoch});
      });
    } catch (e, s) {
      AppLogger.warning('Relay connect failed: $e', subCategory: 'relay');
      AppLogger.debug('$s', subCategory: 'relay');
      _emitStatus(
        RelayConnectionStatus(connected: false, error: 'Relay connect failed'),
      );
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _shouldStayConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastInboundAt = null;
    _lastPongAt = null;
    await _closeChannel();
    _emitStatus(const RelayConnectionStatus(connected: false));
  }

  Future<void> publishHint(RelayHintMessage hint) async {
    if (_channel == null || !_shouldStayConnected) {
      return;
    }

    _send({'type': 'publish_hint', 'payload': hint.toJson()});
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

  Future<String> _bootstrap({
    required String groupId,
    required String userId,
    required String clientId,
  }) async {
    final response = await _dio.post<dynamic>(
      _bootstrapUrl,
      data: {
        'groupId': groupId,
        'userId': userId,
        'clientId': clientId,
        'version': '1',
      },
      options: Options(headers: {'content-type': 'application/json'}),
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
      _runtimeDisabledUntil = _now().add(Duration(seconds: retryAfterSeconds));
      throw StateError('Relay runtime disabled by server');
    }

    final wsUrl = data['wsUrl']?.toString();
    if (wsUrl == null || wsUrl.isEmpty) {
      throw StateError('Missing wsUrl from relay bootstrap');
    }
    return wsUrl;
  }

  void _handleRawMessage(dynamic event) {
    if (event is! String) {
      return;
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      payload = decoded;
    } catch (_) {
      return;
    }
    _lastInboundAt = _now();

    final type = payload['type']?.toString();
    if (type == 'pong') {
      _lastPongAt = _lastInboundAt;
      return;
    }

    if (type == 'hint') {
      final rawHint = payload['payload'];
      if (rawHint is! Map<String, dynamic>) {
        return;
      }
      final hint = RelayHintMessage.fromJson(rawHint);
      if (!hint.isStructurallyValid || hint.isExpired()) {
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
          (payload['retryAfterSeconds'] as num?)?.toInt() ??
          AppConstants.relayCircuitBreakerCooldownSeconds;
      _runtimeDisabledUntil = _now().add(Duration(seconds: retryAfterSeconds));
      _emitStatus(
        RelayConnectionStatus(
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _lastInboundAt = null;
    _lastPongAt = null;
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _scheduleReconnect() {
    if (!_shouldStayConnected || _isDisposed) {
      return;
    }
    if (_targetGroupId == null ||
        _targetUserId == null ||
        _targetClientId == null) {
      return;
    }
    if (_runtimeDisabledUntil != null &&
        _runtimeDisabledUntil!.isAfter(_now())) {
      return;
    }

    _reconnectTimer?.cancel();
    final delaySeconds = _nextReconnectDelaySeconds();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_isDisposed || !_shouldStayConnected) {
        return;
      }
      unawaited(
        connect(
          groupId: _targetGroupId!,
          userId: _targetUserId!,
          clientId: _targetClientId!,
        ),
      );
    });
  }

  int _nextReconnectDelaySeconds() {
    _reconnectAttempt += 1;
    return computeReconnectDelaySeconds(
      attempt: _reconnectAttempt,
      baseSeconds: AppConstants.relayReconnectBaseSeconds,
      maxSeconds: AppConstants.relayReconnectMaxSeconds,
      random: _random,
    );
  }

  @visibleForTesting
  static int computeReconnectDelaySeconds({
    required int attempt,
    required int baseSeconds,
    required int maxSeconds,
    required math.Random random,
  }) {
    final exponent = attempt.clamp(1, 6);
    final exponentialBase = baseSeconds * (1 << (exponent - 1));
    final capped = math.min(exponentialBase, maxSeconds);
    final lowerBound = math.max(1, (capped * 3) ~/ 4);
    return lowerBound + random.nextInt(capped - lowerBound + 1);
  }

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
}
