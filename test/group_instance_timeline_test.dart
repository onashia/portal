import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:portal/models/group_instance_with_group.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/group_instance_timeline.dart';

import 'test_helpers/fake_vrchat_models.dart';
import 'test_helpers/provider_test_notifiers.dart';

void main() {
  testWidgets('renders group names and newest marker', (tester) async {
    final world = buildTestWorld(id: 'wrld_1', name: 'World One');
    final oldDetectedAtUtc = DateTime.utc(2026, 2, 13, 9);
    final newDetectedAtUtc = DateTime.utc(2026, 2, 13, 10);
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
            firstDetectedAt: oldDetectedAtUtc,
          ),
          GroupInstanceWithGroup(
            instance: buildTestInstance(
              instanceId: 'inst_new',
              world: world,
              userCount: 6,
            ),
            groupId: 'grp_alpha',
            firstDetectedAt: newDetectedAtUtc,
          ),
        ],
      },
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
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: GroupInstanceTimeline(userId: 'usr_test'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsNWidgets(2));
    expect(find.text('New'), findsOneWidget);
    expect(
      find.text(DateFormat.jm().format(oldDetectedAtUtc.toLocal())),
      findsOneWidget,
    );
    expect(
      find.text(DateFormat.jm().format(newDetectedAtUtc.toLocal())),
      findsOneWidget,
    );
  });

  testWidgets(
    'renders duplicate instance IDs without duplicate-key exceptions',
    (tester) async {
      final world = buildTestWorld(id: 'wrld_1', name: 'World One');
      final detectedAtUtc = DateTime.utc(2026, 2, 13, 10);
      final monitorState = GroupMonitorState(
        allGroups: [buildTestGroup(groupId: 'grp_alpha', name: 'Alpha')],
        selectedGroupIds: {'grp_alpha'},
        groupInstances: {
          'grp_alpha': [
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_dup',
                world: world,
                userCount: 3,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: detectedAtUtc,
            ),
            GroupInstanceWithGroup(
              instance: buildTestInstance(
                instanceId: 'inst_dup',
                world: world,
                userCount: 5,
              ),
              groupId: 'grp_alpha',
              firstDetectedAt: detectedAtUtc.add(const Duration(minutes: 5)),
            ),
          ],
        },
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
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: GroupInstanceTimeline(userId: 'usr_test'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Alpha'), findsNWidgets(2));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    },
  );

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
          ).overrideWith(() => TestGroupMonitorNotifier(monitorState)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: GroupInstanceTimeline(userId: 'usr_test'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No Groups Selected'), findsOneWidget);
  });

  testWidgets('renders explicit error empty state when fetch errors exist', (
    tester,
  ) async {
    const monitorState = GroupMonitorState(
      selectedGroupIds: {'grp_alpha'},
      groupInstances: {},
      groupErrors: {'grp_alpha': 'Failed to fetch instances'},
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
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: GroupInstanceTimeline(userId: 'usr_test'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Unable to Load Instances'), findsOneWidget);
  });

  testWidgets('keeps normal empty-state message when no errors exist', (
    tester,
  ) async {
    const monitorState = GroupMonitorState(
      selectedGroupIds: {'grp_alpha'},
      groupInstances: {},
      groupErrors: {},
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
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: GroupInstanceTimeline(userId: 'usr_test'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No Instances Open'), findsOneWidget);
  });
}
