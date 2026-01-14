import 'package:flutter_riverpod/flutter_riverpod.dart';

class ApiCallCounterState {
  final int totalCalls;

  const ApiCallCounterState({this.totalCalls = 0});

  ApiCallCounterState copyWith({int? totalCalls}) {
    return ApiCallCounterState(totalCalls: totalCalls ?? this.totalCalls);
  }
}

class ApiCallCounterNotifier extends Notifier<ApiCallCounterState> {
  @override
  ApiCallCounterState build() => const ApiCallCounterState();

  void incrementApiCall() {
    state = state.copyWith(totalCalls: state.totalCalls + 1);
  }

  void reset() {
    state = const ApiCallCounterState();
  }
}

final apiCallCounterProvider =
    NotifierProvider<ApiCallCounterNotifier, ApiCallCounterState>(
        ApiCallCounterNotifier.new);
