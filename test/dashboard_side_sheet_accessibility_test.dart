import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/pages/dashboard_page.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/vrchat_status_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/custom_title_bar.dart';
import 'package:portal/widgets/dashboard/dashboard_action_area.dart';
import 'package:portal/widgets/dashboard/dashboard_side_sheet_layout.dart';
import 'package:portal/widgets/dashboard/selected_group_chip.dart';
import 'package:portal/widgets/common/focusable_extended_fab.dart';
import 'package:portal/widgets/group_selection_side_sheet.dart';
import 'package:portal/widgets/inputs/app_text_field.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import 'test_helpers/auth_test_harness.dart';
import 'test_helpers/fake_vrchat_models.dart';
import 'test_helpers/provider_test_notifiers.dart';

class _MockCurrentUser extends Mock implements CurrentUser {}

class _DashboardTestGroupMonitorNotifier extends GroupMonitorNotifier {
  _DashboardTestGroupMonitorNotifier(this._initialState, {required String arg})
    : super(arg);

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;

  @override
  Future<void> fetchUserGroupsIfNeeded({int minIntervalSeconds = 5}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'opening the sheet moves focus into search and keeps content blocked until close animation completes',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await _pumpDashboardPage(tester);

      await tester.tap(find.byKey(DashboardActionArea.manageGroupsButtonKey));
      await tester.pumpAndSettle();

      final searchField = tester.widget<AppTextField>(
        find.byKey(GroupSelectionSideSheet.searchFieldKey),
      );
      final contentSemanticsGate = tester.widget<ExcludeSemantics>(
        find.byKey(DashboardPage.contentSemanticsGateKey),
      );

      expect(searchField.focusNode?.hasFocus, isTrue);
      expect(contentSemanticsGate.excluding, isTrue);
      expect(
        find.bySemanticsLabel(
          DashboardSideSheetLayout.dismissBarrierSemanticsLabel,
        ),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      final closingSemanticsGate = tester.widget<ExcludeSemantics>(
        find.byKey(DashboardPage.contentSemanticsGateKey),
      );
      expect(closingSemanticsGate.excluding, isTrue);
      expect(_manageGroupsButtonHasFocus(tester), isFalse);

      await tester.pumpAndSettle();

      final manageGroupsFab = tester.widget<FocusableExtendedFab>(
        find.byKey(DashboardActionArea.manageGroupsButtonKey),
      );
      final restoredSemanticsGate = tester.widget<ExcludeSemantics>(
        find.byKey(DashboardPage.contentSemanticsGateKey),
      );
      expect(manageGroupsFab.focusNode?.hasFocus, isTrue);
      expect(restoredSemanticsGate.excluding, isFalse);

      final updatedSearchField = tester.widget<AppTextField>(
        find.byKey(GroupSelectionSideSheet.searchFieldKey),
      );
      expect(updatedSearchField.focusNode?.hasFocus, isFalse);
      semantics.dispose();
    },
  );

  testWidgets(
    'focus traversal skips obscured dashboard content while the action area stays reachable',
    (tester) async {
      await _pumpDashboardPage(tester);

      await tester.tap(find.byKey(DashboardActionArea.manageGroupsButtonKey));
      await tester.pumpAndSettle();

      var actionAreaReached = false;
      for (var i = 0; i < 20; i += 1) {
        expect(_focusWithin<SelectedGroupChip>(), isFalse);
        if (_manageGroupsButtonHasFocus(tester)) {
          actionAreaReached = true;
          break;
        }
        FocusManager.instance.primaryFocus?.nextFocus();
        await tester.pump();
      }

      expect(actionAreaReached, isTrue);
      expect(_focusWithin<SelectedGroupChip>(), isFalse);
    },
  );

  testWidgets(
    'closing the sheet preserves title bar focus when the user moved there intentionally',
    (tester) async {
      await _pumpDashboardPage(tester);

      await tester.tap(find.byKey(DashboardActionArea.manageGroupsButtonKey));
      await tester.pumpAndSettle();

      var titleBarReached = false;
      for (var i = 0; i < 30; i += 1) {
        if (_focusWithin<CustomTitleBar>()) {
          titleBarReached = true;
          break;
        }
        FocusManager.instance.primaryFocus?.nextFocus();
        await tester.pump();
      }

      expect(titleBarReached, isTrue);

      await tester.tap(find.byKey(DashboardSideSheetLayout.dismissBarrierKey));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_focusWithin<CustomTitleBar>(), isTrue);
      expect(_manageGroupsButtonHasFocus(tester), isFalse);
    },
  );

  testWidgets(
    'pressing Escape from title bar focus closes the sheet and preserves title bar focus',
    (tester) async {
      await _pumpDashboardPage(tester);

      await tester.tap(find.byKey(DashboardActionArea.manageGroupsButtonKey));
      await tester.pumpAndSettle();

      var titleBarReached = false;
      for (var i = 0; i < 30; i += 1) {
        if (_focusWithin<CustomTitleBar>()) {
          titleBarReached = true;
          break;
        }
        FocusManager.instance.primaryFocus?.nextFocus();
        await tester.pump();
      }

      expect(titleBarReached, isTrue);
      expect(find.byKey(DashboardSideSheetLayout.dismissBarrierKey), findsOne);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(DashboardSideSheetLayout.dismissBarrierKey),
        findsNothing,
      );
      expect(_focusWithin<CustomTitleBar>(), isTrue);
      expect(_manageGroupsButtonHasFocus(tester), isFalse);
    },
  );
}

Future<void> _pumpDashboardPage(WidgetTester tester) async {
  const userId = 'usr_test';
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final currentUser = _mockCurrentUser();
  final monitorNotifier = _DashboardTestGroupMonitorNotifier(
    GroupMonitorState(
      allGroups: [
        buildTestGroup(groupId: 'grp_selected', name: 'Selected Group'),
        buildTestGroup(groupId: 'grp_available', name: 'Available Group'),
      ],
      selectedGroupIds: const {'grp_selected'},
      isLoading: false,
      isMonitoring: true,
    ),
    arg: userId,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(
          () => TestAuthNotifier(
            AuthState(
              status: AuthStatus.authenticated,
              currentUser: currentUser,
            ),
          ),
        ),
        groupMonitorProvider(userId).overrideWith(() => monitorNotifier),
        groupCalendarProvider(userId).overrideWith(
          () => TestGroupCalendarNotifier(
            const GroupCalendarState(isLoading: false),
            userId: userId,
          ),
        ),
        vrchatStatusProvider.overrideWith(
          () => TestVrchatStatusNotifier(
            const VrchatStatusState(isLoading: false, errorMessage: 'offline'),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const DashboardPage(),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

CurrentUser _mockCurrentUser() {
  final user = _MockCurrentUser();
  when(() => user.id).thenReturn('usr_test');
  when(() => user.displayName).thenReturn('Portal User');
  when(() => user.pronouns).thenReturn('they/them');
  when(() => user.statusDescription).thenReturn('Watching instances');
  when(() => user.status).thenReturn(UserStatus.active);
  when(() => user.profilePicOverrideThumbnail).thenReturn('');
  when(() => user.currentAvatarThumbnailImageUrl).thenReturn('');
  return user;
}

bool _focusWithin<T extends Widget>() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) {
    return false;
  }

  return focusContext.findAncestorWidgetOfExactType<T>() != null;
}

bool _manageGroupsButtonHasFocus(WidgetTester tester) {
  final fab = tester.widget<FocusableExtendedFab>(
    find.byKey(DashboardActionArea.manageGroupsButtonKey),
  );
  return fab.focusNode?.hasFocus == true;
}
