import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/dashboard/dashboard_group_monitoring_section.dart';
import 'package:portal/widgets/dashboard/selected_group_chip.dart';

import 'test_helpers/fake_vrchat_models.dart';
import 'test_helpers/provider_test_notifiers.dart';

void main() {
  testWidgets('passes selected-group error and boost state into chips', (
    tester,
  ) async {
    final monitorState = GroupMonitorState(
      allGroups: [
        buildTestGroup(groupId: 'grp_alpha', name: 'Alpha'),
        buildTestGroup(groupId: 'grp_beta', name: 'Beta'),
      ],
      selectedGroupIds: const {'grp_alpha', 'grp_beta'},
      boostedGroupId: 'grp_alpha',
      isBoostActive: true,
      isMonitoring: true,
      groupErrors: const {'grp_alpha': 'Failed to fetch instances'},
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
            body: SizedBox(
              height: 500,
              child: DashboardGroupMonitoringSection(userId: 'usr_test'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final chips = tester
        .widgetList<SelectedGroupChip>(find.byType(SelectedGroupChip))
        .toList();
    final alphaChip = chips.singleWhere(
      (chip) => chip.group.groupId == 'grp_alpha',
    );
    final betaChip = chips.singleWhere(
      (chip) => chip.group.groupId == 'grp_beta',
    );
    final alphaChipFinder = find.ancestor(
      of: find.text('Alpha'),
      matching: find.byType(SelectedGroupChip),
    );
    final betaChipFinder = find.ancestor(
      of: find.text('Beta'),
      matching: find.byType(SelectedGroupChip),
    );

    expect(alphaChip.hasError, isTrue);
    expect(alphaChip.errorMessage, 'Failed to fetch instances');
    expect(alphaChip.isBoosted, isTrue);
    expect(betaChip.hasError, isFalse);
    expect(betaChip.isBoosted, isFalse);
    expect(
      find.descendant(
        of: alphaChipFinder,
        matching: find.byIcon(Icons.error_outline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: alphaChipFinder,
        matching: find.byIcon(Icons.flash_on),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: betaChipFinder,
        matching: find.byIcon(Icons.error_outline),
      ),
      findsNothing,
    );
  });
}
