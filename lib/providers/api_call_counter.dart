import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_rate_limit_coordinator.dart';

@immutable
class ApiCallCounterState {
  final int totalCalls;
  final Map<String, int> callsByLane;
  final int throttledSkips;

  const ApiCallCounterState({
    this.totalCalls = 0,
    this.callsByLane = const <String, int>{},
    this.throttledSkips = 0,
  });

  ApiCallCounterState copyWith({
    int? totalCalls,
    Map<String, int>? callsByLane,
    int? throttledSkips,
  }) {
    return ApiCallCounterState(
      totalCalls: totalCalls ?? this.totalCalls,
      callsByLane: callsByLane ?? this.callsByLane,
      throttledSkips: throttledSkips ?? this.throttledSkips,
    );
  }
}

class ApiCallCounterNotifier extends Notifier<ApiCallCounterState> {
  @override
  ApiCallCounterState build() => const ApiCallCounterState();

  void incrementApiCall({ApiRequestLane? lane}) {
    final nextCallsByLane = Map<String, int>.from(state.callsByLane);
    if (lane != null) {
      final key = lane.name;
      nextCallsByLane[key] = (nextCallsByLane[key] ?? 0) + 1;
    }

    state = state.copyWith(
      totalCalls: state.totalCalls + 1,
      callsByLane: nextCallsByLane,
    );
  }

  void incrementThrottledSkip({ApiRequestLane? lane}) {
    final nextCallsByLane = Map<String, int>.from(state.callsByLane);
    if (lane != null && !nextCallsByLane.containsKey(lane.name)) {
      nextCallsByLane[lane.name] = 0;
    }

    state = state.copyWith(
      callsByLane: nextCallsByLane,
      throttledSkips: state.throttledSkips + 1,
    );
  }

  void reset() {
    state = const ApiCallCounterState();
  }
}

final apiCallCounterProvider =
    NotifierProvider<ApiCallCounterNotifier, ApiCallCounterState>(
      ApiCallCounterNotifier.new,
    );
