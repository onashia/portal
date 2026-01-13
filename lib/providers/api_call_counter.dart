import 'package:flutter_riverpod/legacy.dart';

class ApiCallCounterState {
  final int totalCalls;

  const ApiCallCounterState({this.totalCalls = 0});

  ApiCallCounterState copyWith({int? totalCalls}) {
    return ApiCallCounterState(totalCalls: totalCalls ?? this.totalCalls);
  }
}

class ApiCallCounterNotifier extends StateNotifier<ApiCallCounterState> {
  ApiCallCounterNotifier() : super(const ApiCallCounterState());

  void incrementApiCall() {
    state = state.copyWith(totalCalls: state.totalCalls + 1);
  }

  void reset() {
    state = const ApiCallCounterState();
  }
}

final apiCallCounterProvider =
    StateNotifierProvider<ApiCallCounterNotifier, ApiCallCounterState>((ref) {
      return ApiCallCounterNotifier();
    });
