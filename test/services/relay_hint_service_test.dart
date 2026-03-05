import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

  group('RelayHintService.computeReconnectDelaySeconds', () {
    test('stays within expected ranges by reconnect attempt', () {
      final expectedRanges = <int, ({int min, int max})>{
        1: (min: 1, max: 2),
        2: (min: 3, max: 4),
        3: (min: 6, max: 8),
        4: (min: 12, max: 16),
        5: (min: 15, max: 20),
        6: (min: 15, max: 20),
      };

      for (final entry in expectedRanges.entries) {
        final delay = RelayHintService.computeReconnectDelaySeconds(
          attempt: entry.key,
          baseSeconds: AppConstants.relayReconnectBaseSeconds,
          maxSeconds: AppConstants.relayReconnectMaxSeconds,
          random: math.Random(entry.key),
        );
        expect(delay, inInclusiveRange(entry.value.min, entry.value.max));
      }
    });

    test('never exceeds the configured max delay', () {
      final random = math.Random(42);
      for (var attempt = 1; attempt <= 30; attempt += 1) {
        for (var run = 0; run < 50; run += 1) {
          final delay = RelayHintService.computeReconnectDelaySeconds(
            attempt: attempt,
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
            random: random,
          );
          expect(
            delay,
            lessThanOrEqualTo(AppConstants.relayReconnectMaxSeconds),
          );
          expect(delay, greaterThanOrEqualTo(1));
        }
      }
    });

    test('keeps non-trivial jitter spread when delay is capped', () {
      final random = math.Random(7);
      final delays = <int>{};
      for (var run = 0; run < 120; run += 1) {
        delays.add(
          RelayHintService.computeReconnectDelaySeconds(
            attempt: 8,
            baseSeconds: AppConstants.relayReconnectBaseSeconds,
            maxSeconds: AppConstants.relayReconnectMaxSeconds,
            random: random,
          ),
        );
      }

      expect(delays.every((delay) => delay >= 15 && delay <= 20), isTrue);
      expect(delays.length, greaterThan(1));
    });
  });

  group('RelayHintService.isHeartbeatStale', () {
    test('returns false before staleness threshold', () {
      final lastInboundAt = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final isStale = RelayHintService.isHeartbeatStale(
        now: lastInboundAt.add(const Duration(seconds: 59)),
        lastInboundAt: lastInboundAt,
        staleAfter: const Duration(seconds: 60),
      );

      expect(isStale, isFalse);
    });

    test('returns true at and after staleness threshold', () {
      final lastInboundAt = DateTime.utc(2026, 1, 1, 0, 0, 0);

      final isStaleAtThreshold = RelayHintService.isHeartbeatStale(
        now: lastInboundAt.add(const Duration(seconds: 60)),
        lastInboundAt: lastInboundAt,
        staleAfter: const Duration(seconds: 60),
      );
      final isStaleAfterThreshold = RelayHintService.isHeartbeatStale(
        now: lastInboundAt.add(const Duration(seconds: 61)),
        lastInboundAt: lastInboundAt,
        staleAfter: const Duration(seconds: 60),
      );

      expect(isStaleAtThreshold, isTrue);
      expect(isStaleAfterThreshold, isTrue);
    });
  });
}
