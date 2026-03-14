import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/debug_info_card.dart';
import 'test_helpers/provider_test_notifiers.dart';

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
          ).overrideWith(() => TestGroupMonitorNotifier(monitorState)),
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

    expect(find.text('API Lanes'), findsOneWidget);
    expect(find.text('Auto Invite'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'debug info card scrolls instead of overflowing in short spaces',
    (tester) async {
      final monitorState = GroupMonitorState(
        isMonitoring: true,
        selectedGroupIds: const {'grp_alpha'},
        groupInstances: const {'grp_alpha': []},
        groupErrors: Map.fromEntries(
          List.generate(
            6,
            (index) => MapEntry('grp_$index', 'Debug error message $index'),
          ),
        ),
        lastRelayError: 'Relay error details that should remain reachable',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupMonitorProvider(
              'usr_test',
            ).overrideWith(() => TestGroupMonitorNotifier(monitorState)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 520,
                  height: 220,
                  child: DebugInfoCard(userId: 'usr_test', useCard: false),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
