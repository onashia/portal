import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/services/relay_heartbeat_monitor.dart';

void main() {
  group('RelayHeartbeatMonitor', () {
    test('isStale is true before start() is called', () {
      final monitor = RelayHeartbeatMonitor();
      expect(monitor.isStale, isTrue);
    });

    test('isStale is false immediately after start()', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        final monitor = RelayHeartbeatMonitor(
          interval: const Duration(seconds: 20),
          staleAfter: const Duration(seconds: 60),
          now: () => start.add(async.elapsed),
        );

        monitor.start(sendPing: (_) {}, onStale: () {});

        expect(monitor.isStale, isFalse);
        monitor.stop();
      });
    });

    test(
      'isStale is true when elapsed time exceeds staleAfter with no pong',
      () {
        fakeAsync((async) {
          final start = DateTime.utc(2026, 1, 1);
          final monitor = RelayHeartbeatMonitor(
            interval: const Duration(seconds: 20),
            staleAfter: const Duration(seconds: 60),
            now: () => start.add(async.elapsed),
          );

          monitor.start(sendPing: (_) {}, onStale: () {});

          // Advance just past the stale threshold without recording a pong.
          async.elapse(const Duration(seconds: 61));

          expect(monitor.isStale, isTrue);
        });
      },
    );

    test('recordPong resets the stale-detection window', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        final monitor = RelayHeartbeatMonitor(
          interval: const Duration(seconds: 20),
          staleAfter: const Duration(seconds: 60),
          now: () => start.add(async.elapsed),
        );

        monitor.start(sendPing: (_) {}, onStale: () {});

        // Advance to just before stale, then record a pong.
        async.elapse(const Duration(seconds: 59));
        expect(monitor.isStale, isFalse);
        monitor.recordPong(); // lastPongAt now at t=59s

        // Advance another 30s (89s total). The pong was at t=59s, so the
        // new window expires at t=119s — still not stale.
        async.elapse(const Duration(seconds: 30));
        expect(monitor.isStale, isFalse);

        monitor.stop();
      });
    });

    test('sendPing is called on each interval tick while not stale', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        final pings = <DateTime>[];
        final monitor = RelayHeartbeatMonitor(
          interval: const Duration(seconds: 20),
          // Long enough that all 3 ticks (at 20s, 40s, 60s) stay non-stale.
          staleAfter: const Duration(seconds: 100),
          now: () => start.add(async.elapsed),
        );

        monitor.start(sendPing: pings.add, onStale: () {});

        async.elapse(const Duration(seconds: 60)); // 3 ticks

        expect(pings.length, 3);
        monitor.stop();
      });
    });

    test('onStale fires (and sendPing does not) on the first stale tick', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        var onStaleCalled = false;
        var pingCount = 0;

        final monitor = RelayHeartbeatMonitor(
          interval: const Duration(seconds: 20),
          staleAfter: const Duration(seconds: 60),
          now: () => start.add(async.elapsed),
        );

        monitor.start(
          sendPing: (_) => pingCount++,
          onStale: () => onStaleCalled = true,
        );

        // Ticks at 20s and 40s send pings. Tick at 60s is the stale boundary:
        // lastPongAt == start, start + 60s is NOT after start + 60s, so stale.
        async.elapse(const Duration(seconds: 60));

        expect(onStaleCalled, isTrue);
        expect(pingCount, 2); // only the non-stale ticks sent pings
      });
    });

    test('stop cancels the timer and prevents further pings', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        var pingCount = 0;

        final monitor = RelayHeartbeatMonitor(
          interval: const Duration(seconds: 20),
          staleAfter: const Duration(seconds: 60),
          now: () => start.add(async.elapsed),
        );

        monitor.start(sendPing: (_) => pingCount++, onStale: () {});
        monitor.stop();

        // Advance well past the interval — no timers should fire.
        async.elapse(const Duration(seconds: 100));

        expect(pingCount, 0);
      });
    });

    test('calling start() a second time reseeds lastPongAt', () {
      fakeAsync((async) {
        final start = DateTime.utc(2026, 1, 1);
        final monitor = RelayHeartbeatMonitor(
          interval: const Duration(seconds: 20),
          staleAfter: const Duration(seconds: 60),
          now: () => start.add(async.elapsed),
        );

        monitor.start(sendPing: (_) {}, onStale: () {});

        // Advance past the stale threshold so isStale becomes true.
        async.elapse(const Duration(seconds: 61));
        expect(monitor.isStale, isTrue);

        // Calling start() again reseeds lastPongAt to the current time,
        // so the monitor is no longer immediately stale.
        monitor.start(sendPing: (_) {}, onStale: () {});
        expect(monitor.isStale, isFalse);

        monitor.stop();
      });
    });
  });
}
