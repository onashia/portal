import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/dashboard/dashboard_cards.dart';

import 'test_helpers/fake_vrchat_models.dart';

class _TestGroupMonitorNotifier extends GroupMonitorNotifier {
  _TestGroupMonitorNotifier(this._initialState) : super('usr_test');

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;
}

class _TestGroupCalendarNotifier extends GroupCalendarNotifier {
  _TestGroupCalendarNotifier(this._initialState) : super('usr_test');

  final GroupCalendarState _initialState;

  @override
  GroupCalendarState build() => _initialState;
}

void main() {
  testWidgets('stacked dashboard cards layout renders without overflow', (
    tester,
  ) async {
    final world = buildTestWorld(id: 'wrld_1', name: 'World One');

    final monitorState = GroupMonitorState(
      allGroups: [buildTestGroup(groupId: 'grp_alpha', name: 'Alpha')],
      selectedGroupIds: {'grp_alpha'},
      groupInstances: {
        'grp_alpha': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_1',
              world: world,
              userCount: 4,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 10),
          ),
        ],
      },
    );

    const calendarState = GroupCalendarState(
      isLoading: false,
      todayEvents: [],
      groupErrors: {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupMonitorProvider(
            'usr_test',
          ).overrideWith(() => _TestGroupMonitorNotifier(monitorState)),
          groupCalendarProvider(
            'usr_test',
          ).overrideWith(() => _TestGroupCalendarNotifier(calendarState)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 420,
                child: DashboardCards(
                  userId: 'usr_test',
                  canShowSideBySide: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(DashboardCards), findsOneWidget);
    expect(tester.takeException(), isNull);

    final verticalScrollView = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.vertical,
    );
    await tester.drag(verticalScrollView.first, const Offset(0, -120));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
