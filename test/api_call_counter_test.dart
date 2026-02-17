import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';

void main() {
  test('incrementApiCall keeps backward compatibility without lane', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(apiCallCounterProvider.notifier).incrementApiCall();

    final state = container.read(apiCallCounterProvider);
    expect(state.totalCalls, 1);
    expect(state.callsByLane, isEmpty);
  });

  test('incrementApiCall tracks lane counters when provided', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(apiCallCounterProvider.notifier);
    notifier.incrementApiCall(lane: ApiRequestLane.groupBaseline);
    notifier.incrementApiCall(lane: ApiRequestLane.groupBaseline);
    notifier.incrementApiCall(lane: ApiRequestLane.calendar);

    final state = container.read(apiCallCounterProvider);
    expect(state.totalCalls, 3);
    expect(state.callsByLane['groupBaseline'], 2);
    expect(state.callsByLane['calendar'], 1);
  });

  test('incrementThrottledSkip updates skip count without changing total', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(apiCallCounterProvider.notifier);
    notifier.incrementApiCall(lane: ApiRequestLane.groupBaseline);
    notifier.incrementThrottledSkip(lane: ApiRequestLane.groupBaseline);

    final state = container.read(apiCallCounterProvider);
    expect(state.totalCalls, 1);
    expect(state.throttledSkips, 1);
    expect(state.callsByLane['groupBaseline'], 1);
  });
}
