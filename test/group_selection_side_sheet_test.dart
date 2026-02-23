import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/theme/side_sheet_theme.dart';
import 'package:portal/widgets/group_selection_side_sheet.dart';

import 'test_helpers/fake_vrchat_models.dart';

class _TestGroupMonitorNotifier extends GroupMonitorNotifier {
  _TestGroupMonitorNotifier(this._initialState) : super('usr_test');

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;

  @override
  Future<void> fetchUserGroupsIfNeeded({int minIntervalSeconds = 5}) async {}
}

void main() {
  testWidgets(
    'does not rebuild side sheet on unrelated monitor state changes',
    (tester) async {
      final initialState = GroupMonitorState(
        allGroups: [
          buildTestGroup(groupId: 'grp_alpha', name: 'Alpha'),
          buildTestGroup(groupId: 'grp_beta', name: 'Beta'),
        ],
        selectedGroupIds: {'grp_alpha'},
        isLoading: false,
      );
      final notifier = _TestGroupMonitorNotifier(initialState);
      var rebuildCount = 0;
      final previousRebuildCallback = debugOnRebuildDirtyWidget;
      addTearDown(() {
        debugOnRebuildDirtyWidget = previousRebuildCallback;
      });
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is GroupSelectionSideSheet) {
          rebuildCount += 1;
        }
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            groupMonitorProvider('usr_test').overrideWith(() => notifier),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: GroupSelectionSideSheet(userId: 'usr_test', onClose: () {}),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final baselineBuildCount = rebuildCount;

      notifier.state = notifier.state.copyWith(autoInviteEnabled: false);
      await tester.pump();

      expect(rebuildCount, baselineBuildCount);

      notifier.state = notifier.state.copyWith(isLoading: true);
      await tester.pump();

      expect(rebuildCount, greaterThan(baselineBuildCount));
    },
  );

  testWidgets('uses side-sheet tokens for container, outline, and elevation', (
    tester,
  ) async {
    final state = GroupMonitorState(
      allGroups: [buildTestGroup(groupId: 'grp_alpha', name: 'Alpha')],
      selectedGroupIds: const {},
      isLoading: false,
    );
    final notifier = _TestGroupMonitorNotifier(state);
    final theme = AppTheme.lightTheme;
    final sideSheetTheme = theme.extension<SideSheetTheme>()!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupMonitorProvider('usr_test').overrideWith(() => notifier),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: GroupSelectionSideSheet(userId: 'usr_test', onClose: () {}),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final cardFinder = find.descendant(
      of: find.byType(GroupSelectionSideSheet),
      matching: find.byType(Card),
    );

    expect(cardFinder, findsOneWidget);

    final card = tester.widget<Card>(cardFinder);
    final shape = card.shape! as RoundedRectangleBorder;

    expect(card.color, sideSheetTheme.containerColor);
    expect(card.elevation, sideSheetTheme.elevation);
    expect(card.shadowColor, sideSheetTheme.shadowColor);
    expect(shape.side.style, BorderStyle.solid);
    expect(shape.side.color, sideSheetTheme.outlineColor);
  });

  test(
    'maps side-sheet container to elevated surface token in both themes',
    () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        final sideSheetTheme = theme.extension<SideSheetTheme>();
        expect(sideSheetTheme, isNotNull);
        expect(
          sideSheetTheme!.containerColor,
          theme.colorScheme.surfaceContainerHigh,
        );
        expect(sideSheetTheme.shadowColor, theme.colorScheme.shadow);
        expect(
          sideSheetTheme.containerColor,
          isNot(theme.colorScheme.surfaceContainerLow),
        );
      }
    },
  );
}
