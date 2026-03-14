import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/models/relay_hint_message.dart';
import 'package:portal/services/relay_bootstrap_client.dart';
import 'package:portal/services/relay_heartbeat_monitor.dart';
import 'package:portal/services/relay_hint_service.dart';
import 'package:portal/services/relay_reconnect_scheduler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FixedRandom implements math.Random {
  _FixedRandom(this._value);

  final int _value;

  @override
  bool nextBool() => _value.isOdd;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => _value.clamp(0, max - 1);
}

class _FakeWebSocketSink implements WebSocketSink {
  _FakeWebSocketSink({
    required void Function(Object? data) onAdd,
    required Future<void> Function() onClose,
  }) : _onAdd = onAdd,
       _onClose = onClose;

  final void Function(Object? data) _onAdd;
  final Future<void> Function() _onClose;
  final StreamController<Object?> _outgoingController =
      StreamController<Object?>.broadcast();
  bool _isClosed = false;

  @override
  void add(Object? data) {
    if (_isClosed) {
      throw StateError('Cannot add to closed websocket sink');
    }
    _outgoingController.add(data);
    _onAdd(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_isClosed) {
      throw StateError('Cannot addError to closed websocket sink');
    }
    _outgoingController.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<Object?> stream) {
    if (_isClosed) {
      throw StateError('Cannot addStream to closed websocket sink');
    }
    return _outgoingController.sink.addStream(stream);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _outgoingController.close();
    await _onClose();
  }

  @override
  Future<void> get done => _outgoingController.done;
}

class _FakeWebSocketChannel extends Fake implements WebSocketChannel {
  _FakeWebSocketChannel({void Function(Object? data)? onClientMessage})
    : _onClientMessage = onClientMessage {
    _sink = _FakeWebSocketSink(
      onAdd: (data) {
        sentMessages.add(data);
        _onClientMessage?.call(data);
      },
      onClose: () async {
        if (!_incomingController.isClosed) {
          await _incomingController.close();
        }
      },
    );
  }

  final void Function(Object? data)? _onClientMessage;
  final StreamController<dynamic> _incomingController =
      StreamController<dynamic>.broadcast();
  final List<Object?> sentMessages = <Object?>[];
  late final _FakeWebSocketSink _sink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready async {}

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _incomingController.stream;

  void emit(Object? payload) {
    if (!_incomingController.isClosed) {
      _incomingController.add(payload);
    }
  }
}

/// Fake WebSocket channel whose [ready] future immediately rejects, simulating
/// a failed WebSocket handshake after the bootstrap succeeds.
class _FailingWebSocketChannel extends Fake implements WebSocketChannel {
  _FailingWebSocketChannel({required this.error});

  final Object error;

  @override
  Future<void> get ready => Future.error(error);

  @override
  WebSocketSink get sink =>
      _FakeWebSocketSink(onAdd: (_) {}, onClose: () async {});

  @override
  Stream<dynamic> get stream => const Stream.empty();
}

/// Fake heartbeat monitor that lets tests trigger stale callbacks on demand,
/// eliminating wall-clock waits from the heartbeat lifecycle tests.
class _FakeHeartbeatMonitor extends Fake implements RelayHeartbeatMonitor {
  void Function(DateTime)? _sendPing;
  void Function()? _onStale;

  @override
  void start({
    required void Function(DateTime now) sendPing,
    required void Function() onStale,
  }) {
    _sendPing = sendPing;
    _onStale = onStale;
  }

  @override
  void stop() {}

  @override
  void recordPong() {}

  @override
  bool get isStale => false;

  @override
  DateTime? get lastPongAt => null;

  /// Simulates a stale heartbeat by invoking the [onStale] callback that was
  /// supplied to [start].
  void triggerStale() {
    stop();
    _onStale?.call();
  }

  // Expose sendPing for tests that verify ping frames are sent.
  void Function(DateTime)? get sendPing => _sendPing;
}

/// Fake bootstrap client that immediately resolves to a fixed WebSocket URI,
/// eliminating the HTTP bootstrap round-trip from connection tests.
class _FakeBootstrapClient extends Fake implements RelayBootstrapClient {
  _FakeBootstrapClient(this._uri);

  final Uri _uri;

  @override
  bool get isConfigured => true;

  @override
  Future<Uri> bootstrap({
    required String groupId,
    required String clientId,
    required DateTime Function() now,
    required void Function(DateTime disabledUntil) onRuntimeDisabled,
  }) async => _uri;
}

/// Fake bootstrap client that immediately throws [DioException], simulating
/// an HTTP-level failure during relay bootstrap.
class _ThrowingBootstrapClient extends Fake implements RelayBootstrapClient {
  @override
  bool get isConfigured => true;

  @override
  Future<Uri> bootstrap({
    required String groupId,
    required String clientId,
    required DateTime Function() now,
    required void Function(DateTime disabledUntil) onRuntimeDisabled,
  }) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/relay/bootstrap'),
    );
  }
}

/// Fake reconnect scheduler that stores the reconnect callback for immediate
/// on-demand firing, removing timer-based delays from reconnect tests.
class _FakeReconnectScheduler extends Fake implements ReconnectScheduler {
  void Function()? _pendingCallback;

  @override
  void schedule(void Function() callback) {
    _pendingCallback = callback;
  }

  @override
  void cancel() {
    _pendingCallback = null;
  }

  @override
  void reset() {
    _pendingCallback = null;
  }

  @override
  int get attemptCount => 0;

  /// Fires the most recently scheduled reconnect callback synchronously.
  void fireScheduled() {
    final cb = _pendingCallback;
    _pendingCallback = null;
    cb?.call();
  }
}

void main() {
  group('RelayHintService heartbeat lifecycle', () {
    // Verifies the stale-heartbeat → disconnect → reconnect path using
    // injected fakes so the test completes without any wall-clock waits.
    test('connect_wait_stale_reconnect', () async {
      final statuses = <RelayConnectionStatus>[];
      var connectCount = 0;

      final fakeHeartbeat = _FakeHeartbeatMonitor();
      final fakeScheduler = _FakeReconnectScheduler();

      final service = RelayHintService(
        bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://relay.test')),
        heartbeatMonitor: fakeHeartbeat,
        reconnectScheduler: fakeScheduler,
        channelConnector: (uri) {
          connectCount += 1;
          return _FakeWebSocketChannel();
        },
      );

      final statusSubscription = service.statuses.listen(statuses.add);
      addTearDown(() async {
        await statusSubscription.cancel();
        await service.dispose();
      });

      // First connect — heartbeat.start() is called, storing onStale callback.
      await service.connect(groupId: 'grp', clientId: 'client');
      expect(connectCount, 1);

      // Trigger stale: disconnect path runs, schedules reconnect on fake.
      fakeHeartbeat.triggerStale();
      await pumpEventQueue(); // let _closeChannel() finish asynchronously

      // Fire the queued reconnect immediately — no timer delay needed.
      fakeScheduler.fireScheduled();
      await pumpEventQueue(); // let connect() complete

      expect(connectCount, greaterThanOrEqualTo(2));
      expect(statuses.first.connected, isTrue);
      expect(statuses.any((status) => status.connected == false), isTrue);
    });

    test('connect_pong_prevents_stale_reconnect', () async {
      var connectCount = 0;

      final service = RelayHintService(
        bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://relay.test')),
        random: _FixedRandom(0),
        heartbeatInterval: const Duration(milliseconds: 20),
        heartbeatStaleAfter: const Duration(milliseconds: 60),
        channelConnector: (uri) {
          connectCount += 1;
          late final _FakeWebSocketChannel channel;
          channel = _FakeWebSocketChannel(
            onClientMessage: (data) {
              if (data is! String) {
                return;
              }
              final decoded = jsonDecode(data);
              if (decoded is! Map<String, dynamic>) {
                return;
              }
              if (decoded['type'] == 'ping') {
                channel.emit(jsonEncode({'type': 'pong', 'ts': decoded['ts']}));
              }
            },
          );
          return channel;
        },
      );

      addTearDown(service.dispose);

      await service.connect(groupId: 'grp', clientId: 'client');
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(connectCount, 1);
      expect(service.isConnected, isTrue);
    });
  });

  group('RelayHintService message handling', () {
    // Valid hint JSON that passes isStructurallyValid and is not expired.
    final farFuture = DateTime.utc(2099);
    final validHintJson = <String, dynamic>{
      'version': '1',
      'hintId': 'hint_1',
      'groupId': 'grp_11111111-1111-1111-1111-111111111111',
      'worldId': 'wrld_12345678-1234-1234-1234-123456789abc',
      'instanceId': '12345~alpha',
      'nUsers': 10,
      'detectedAtMs': DateTime.utc(2026).millisecondsSinceEpoch,
      'expiresAtMs': farFuture.millisecondsSinceEpoch,
      'sourceClientId': 'usr_a',
    };

    /// Returns a connected [RelayHintService] backed by [channel].
    Future<RelayHintService> connectService(
      _FakeWebSocketChannel channel,
    ) async {
      final service = RelayHintService(
        bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://relay.test')),
        heartbeatMonitor: _FakeHeartbeatMonitor(),
        reconnectScheduler: _FakeReconnectScheduler(),
        channelConnector: (_) => channel,
      );
      addTearDown(service.dispose);
      await service.connect(groupId: 'grp', clientId: 'client');
      return service;
    }

    test('valid_hint_is_emitted_on_hints_stream', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      channel.emit(jsonEncode({'type': 'hint', 'payload': validHintJson}));
      await pumpEventQueue();

      expect(hints, hasLength(1));
      expect(hints.first.hintId, 'hint_1');
    });

    test('expired_hint_is_silently_dropped', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      final expiredJson = Map<String, dynamic>.from(validHintJson)
        ..['expiresAtMs'] = DateTime.utc(2000).millisecondsSinceEpoch;
      channel.emit(jsonEncode({'type': 'hint', 'payload': expiredJson}));
      await pumpEventQueue();

      expect(hints, isEmpty);
    });

    test('structurally_invalid_hint_is_silently_dropped', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      final invalidJson = Map<String, dynamic>.from(validHintJson)
        ..['worldId'] = 'not_a_valid_world_id'; // fails regex
      channel.emit(jsonEncode({'type': 'hint', 'payload': invalidJson}));
      await pumpEventQueue();

      expect(hints, isEmpty);
    });

    test('non_map_hint_payload_is_silently_dropped', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      channel.emit(jsonEncode({'type': 'hint', 'payload': 'not_a_map'}));
      await pumpEventQueue();

      expect(hints, isEmpty);
    });

    test('error_message_emits_disconnected_status_with_error_string', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final statuses = <RelayConnectionStatus>[];
      final sub = service.statuses.listen(statuses.add);
      addTearDown(sub.cancel);

      channel.emit(
        jsonEncode({'type': 'error', 'message': 'relay_overloaded'}),
      );
      await pumpEventQueue();

      expect(statuses, isNotEmpty);
      final last = statuses.last;
      expect(last.connected, isFalse);
      expect(last.error, 'relay_overloaded');
    });

    test(
      'disabled_message_sets_runtimeDisabledUntil_and_disconnects',
      () async {
        final fixedNow = DateTime.utc(2026, 3, 3, 12, 0, 0);
        final channel = _FakeWebSocketChannel();
        final service = RelayHintService(
          bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://relay.test')),
          heartbeatMonitor: _FakeHeartbeatMonitor(),
          reconnectScheduler: _FakeReconnectScheduler(),
          channelConnector: (_) => channel,
          now: () => fixedNow,
        );
        addTearDown(service.dispose);
        await service.connect(groupId: 'grp', clientId: 'client');

        channel.emit(
          jsonEncode({'type': 'disabled', 'retryAfterSeconds': 120}),
        );
        await pumpEventQueue();

        expect(service.runtimeDisabledUntil, isNotNull);
        expect(
          service.runtimeDisabledUntil!,
          fixedNow.add(const Duration(seconds: 120)),
        );
        expect(service.isConnected, isFalse);
      },
    );

    test('disabled_message_caps_retryAfterSeconds_at_max', () async {
      final fixedNow = DateTime.utc(2026, 3, 3, 12, 0, 0);
      final channel = _FakeWebSocketChannel();
      final service = RelayHintService(
        bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://relay.test')),
        heartbeatMonitor: _FakeHeartbeatMonitor(),
        reconnectScheduler: _FakeReconnectScheduler(),
        channelConnector: (_) => channel,
        now: () => fixedNow,
      );
      addTearDown(service.dispose);
      await service.connect(groupId: 'grp', clientId: 'client');

      // Server sends an absurdly large value.
      channel.emit(
        jsonEncode({'type': 'disabled', 'retryAfterSeconds': 999999999}),
      );
      await pumpEventQueue();

      final disabledUntil = service.runtimeDisabledUntil;
      expect(disabledUntil, isNotNull);
      final expectedMax = fixedNow.add(
        Duration(seconds: AppConstants.relayMaxRetryAfterSeconds),
      );
      expect(disabledUntil, expectedMax);
    });

    test('binary_frame_is_silently_dropped', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      channel.emit(<int>[0x00, 0x01, 0x02]); // binary (List<int>)
      await pumpEventQueue();

      expect(hints, isEmpty);
    });

    test('non_json_string_is_silently_dropped', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      channel.emit('not valid json {{{{');
      await pumpEventQueue();

      expect(hints, isEmpty);
    });

    test('json_array_is_silently_dropped', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      channel.emit(jsonEncode([1, 2, 3])); // valid JSON but not a Map
      await pumpEventQueue();

      expect(hints, isEmpty);
    });

    test('oversized_message_is_silently_dropped', () async {
      final channel = _FakeWebSocketChannel();
      final service = await connectService(channel);
      final hints = <RelayHintMessage>[];
      final sub = service.hints.listen(hints.add);
      addTearDown(sub.cancel);

      // 8193 characters — just over the 8192-byte limit.
      channel.emit('x' * 8193);
      await pumpEventQueue();

      expect(hints, isEmpty);
    });

    group('publishHint', () {
      test('publishHint_sends_serialized_hint_to_sink', () async {
        final channel = _FakeWebSocketChannel();
        final service = await connectService(channel);

        final hint = RelayHintMessage.create(
          groupId: 'grp_alpha',
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: '12345~alpha',
          nUsers: 5,
          sourceClientId: 'client',
        );
        await service.publishHint(hint);
        await pumpEventQueue();

        expect(channel.sentMessages, isNotEmpty);
        final sent =
            jsonDecode(channel.sentMessages.last as String)
                as Map<String, dynamic>;
        expect(sent['type'], 'publish_hint');
        final payload = sent['payload'] as Map<String, dynamic>;
        expect(payload['hintId'], hint.hintId);
        expect(payload['groupId'], 'grp_alpha');
      });

      test('publishHint_is_noop_when_disconnected', () async {
        final service = RelayHintService(
          bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://relay.test')),
          heartbeatMonitor: _FakeHeartbeatMonitor(),
          reconnectScheduler: _FakeReconnectScheduler(),
          channelConnector: (_) => _FakeWebSocketChannel(),
        );
        addTearDown(service.dispose);
        // Do not call connect() — service is disconnected.

        final hint = RelayHintMessage.create(
          groupId: 'grp_alpha',
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: '12345~alpha',
          nUsers: 5,
          sourceClientId: 'client',
        );
        // Must complete without throwing.
        await expectLater(service.publishHint(hint), completes);
      });

      test('publishHint_drops_oversized_payload', () async {
        final channel = _FakeWebSocketChannel();
        final service = await connectService(channel);

        // The Relay Protocol Contract caps client->worker websocket payloads
        // at relayMaxOutboundPayloadBytes. Pad hintId until the encoded frame
        // crosses that limit.
        final oversizedHint = RelayHintMessage(
          version: '1',
          hintId: 'x' * 2048,
          groupId: 'grp_alpha',
          worldId: 'wrld_12345678-1234-1234-1234-123456789abc',
          instanceId: '12345~alpha',
          nUsers: 5,
          detectedAt: DateTime.fromMillisecondsSinceEpoch(0),
          expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
          sourceClientId: 'client',
        );

        final sinkSizeBefore = channel.sentMessages.length;
        await service.publishHint(oversizedHint);
        await pumpEventQueue();

        expect(
          channel.sentMessages.length,
          sinkSizeBefore,
          reason: 'oversized publish_hint must not be written to the sink',
        );
      });
    });
  });

  group('RelayHintService bootstrap error handling', () {
    test('bootstrap_DioException_schedules_reconnect', () async {
      final fakeScheduler = _FakeReconnectScheduler();
      final statuses = <RelayConnectionStatus>[];

      final service = RelayHintService(
        bootstrapClient: _ThrowingBootstrapClient(),
        heartbeatMonitor: _FakeHeartbeatMonitor(),
        reconnectScheduler: fakeScheduler,
        channelConnector: (_) => _FakeWebSocketChannel(),
      );
      addTearDown(service.dispose);

      final sub = service.statuses.listen(statuses.add);
      addTearDown(sub.cancel);

      await service.connect(groupId: 'grp', clientId: 'client');
      await pumpEventQueue();

      // A reconnect must be scheduled after the bootstrap failure.
      expect(fakeScheduler._pendingCallback, isNotNull);

      // The status stream must emit a disconnected error status.
      expect(statuses, isNotEmpty);
      final errorStatus = statuses.last;
      expect(errorStatus.connected, isFalse);
      expect(errorStatus.error, isNotNull);
    });
  });

  group('RelayHintService channel.ready failure', () {
    test(
      'emits disconnected status and schedules reconnect when ready throws',
      () async {
        final fakeScheduler = _FakeReconnectScheduler();
        final statuses = <RelayConnectionStatus>[];

        final service = RelayHintService(
          bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://test.invalid')),
          heartbeatMonitor: _FakeHeartbeatMonitor(),
          reconnectScheduler: fakeScheduler,
          channelConnector: (_) => _FailingWebSocketChannel(
            error: WebSocketChannelException('handshake failed'),
          ),
        );
        addTearDown(service.dispose);

        final sub = service.statuses.listen(statuses.add);
        addTearDown(sub.cancel);

        await service.connect(groupId: 'grp', clientId: 'client');
        await pumpEventQueue();

        // A reconnect must be scheduled after the ready failure.
        expect(fakeScheduler._pendingCallback, isNotNull);

        // The status stream must emit at least one disconnected status with an
        // error message (the inner catch emits the specific handshake error;
        // _handleDisconnect may emit an additional bare disconnected status).
        expect(statuses, isNotEmpty);
        expect(statuses.every((s) => !s.connected), isTrue);
        expect(statuses.any((s) => s.error != null), isTrue);
      },
    );
  });

  group('RelayHintService dispose during active connection', () {
    test(
      'tears down cleanly without errors or callbacks after dispose',
      () async {
        final fakeChannel = _FakeWebSocketChannel();
        final statuses = <RelayConnectionStatus>[];
        final errors = <Object>[];

        final service = RelayHintService(
          bootstrapClient: _FakeBootstrapClient(Uri.parse('ws://test.invalid')),
          heartbeatMonitor: _FakeHeartbeatMonitor(),
          reconnectScheduler: _FakeReconnectScheduler(),
          channelConnector: (_) => fakeChannel,
        );

        final sub = service.statuses.listen(statuses.add, onError: errors.add);
        addTearDown(sub.cancel);

        await service.connect(groupId: 'grp', clientId: 'client');
        await pumpEventQueue();

        // Confirm we are connected before disposing.
        expect(statuses.any((s) => s.connected), isTrue);

        // Dispose while the connection is active — must not throw.
        service.dispose();
        await pumpEventQueue();

        // No stream errors should have been emitted.
        expect(errors, isEmpty);

        // Further status events are no longer broadcast after dispose.
        final countBeforeEmit = statuses.length;
        fakeChannel.emit('unexpected');
        await pumpEventQueue();
        expect(statuses.length, countBeforeEmit);
      },
    );
  });

}
