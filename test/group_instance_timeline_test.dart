import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/group_instance_timeline.dart';

import 'test_helpers/fake_vrchat_models.dart';

class _TestGroupMonitorNotifier extends GroupMonitorNotifier {
  _TestGroupMonitorNotifier(this._initialState) : super('usr_test');

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;
}

void main() {
  testWidgets('renders group names and newest marker', (tester) async {
    final world = buildTestWorld(id: 'wrld_1', name: 'World One');
    final monitorState = GroupMonitorState(
      allGroups: [buildTestGroup(groupId: 'grp_alpha', name: 'Alpha')],
      selectedGroupIds: {'grp_alpha'},
      newestInstanceId: 'inst_new',
      groupInstances: {
        'grp_alpha': [
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_old',
              world: world,
              userCount: 3,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 9),
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_new',
              world: world,
              userCount: 6,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: DateTime.utc(2026, 2, 13, 10),
          ),
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupMonitorProvider(
            'usr_test',
          ).overrideWith(() => _TestGroupMonitorNotifier(monitorState)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: GroupInstanceTimeline(
                userId: 'usr_test',
                onRefresh: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsNWidgets(2));
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('renders no-group empty state', (tester) async {
    const monitorState = GroupMonitorState(
      selectedGroupIds: {},
      groupInstances: {},
      groupErrors: {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupMonitorProvider(
            'usr_test',
          ).overrideWith(() => _TestGroupMonitorNotifier(monitorState)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: GroupInstanceTimeline(
                userId: 'usr_test',
                onRefresh: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No Groups Selected'), findsOneWidget);
  });
}
