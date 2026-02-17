import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/debug_info_card.dart';

class _TestGroupMonitorNotifier extends GroupMonitorNotifier {
  _TestGroupMonitorNotifier(this._initialState) : super('usr_test');

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;
}

class _TestApiCallCounterNotifier extends ApiCallCounterNotifier {
  _TestApiCallCounterNotifier(this._initialState);

  final ApiCallCounterState _initialState;

  @override
  ApiCallCounterState build() => _initialState;
}

void main() {
  testWidgets('debug info card does not overflow with long metric values', (
    tester,
  ) async {
    const monitorState = GroupMonitorState(
      isMonitoring: true,
      selectedGroupIds: {'grp_alpha'},
      groupInstances: {'grp_alpha': []},
    );
    const counterState = ApiCallCounterState(
      totalCalls: 12345,
      throttledSkips: 321,
      callsByLane: {
        'groupBaselineWithVeryLongName': 999,
        'calendarWithVeryLongName': 998,
        'statusWithVeryLongName': 997,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupMonitorProvider(
            'usr_test',
          ).overrideWith(() => _TestGroupMonitorNotifier(monitorState)),
          apiCallCounterProvider.overrideWith(
            () => _TestApiCallCounterNotifier(counterState),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                child: DebugInfoCard(userId: 'usr_test', useCard: false),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
