import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/dashboard/dashboard_side_sheet_layout.dart';

void main() {
  const testSheetWidth = 320.0;

  testWidgets('tap outside side sheet calls onClose, tap inside does not', (
    tester,
  ) async {
    var closeCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: DashboardSideSheetLayout(
            content: const SizedBox.expand(),
            sideSheet: Container(
              key: const Key('side_sheet'),
              color: Colors.blueGrey,
            ),
            sheetWidth: testSheetWidth,
            progress: 1,
            onClose: () => closeCount += 1,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final sheetFinder = find.byKey(const Key('side_sheet'));
    expect(sheetFinder, findsOneWidget);

    await tester.tapAt(tester.getCenter(sheetFinder));
    await tester.pump();

    expect(closeCount, 0);

    final sheetTopLeft = tester.getTopLeft(sheetFinder);
    final outsidePoint = Offset(sheetTopLeft.dx - 24, sheetTopLeft.dy + 24);

    expect(outsidePoint.dx, greaterThan(0));
    await tester.tapAt(outsidePoint);
    await tester.pump();

    expect(closeCount, 1);
  });

  testWidgets('shell width includes left shadow gutter and right inset', (
    tester,
  ) async {
    final theme = AppTheme.lightTheme;
    final m3e =
        theme.extension<M3ETheme>() ?? M3ETheme.defaults(theme.colorScheme);
    final expectedWidth = testSheetWidth + m3e.spacing.lg + m3e.spacing.md;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: DashboardSideSheetLayout(
            content: const SizedBox.expand(),
            sideSheet: Container(
              key: const Key('side_sheet'),
              color: Colors.blueGrey,
            ),
            sheetWidth: testSheetWidth,
            progress: 1,
            onClose: () {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final shellRect = tester.getRect(
      find.byKey(DashboardSideSheetLayout.shellKey),
    );
    expect(shellRect.width, closeTo(expectedWidth, 0.001));
  });

  testWidgets(
    'side sheet right, bottom, and top placement remain aligned to insets',
    (tester) async {
      final theme = AppTheme.lightTheme;
      final m3e =
          theme.extension<M3ETheme>() ?? M3ETheme.defaults(theme.colorScheme);
      final topInset = m3e.spacing.sm;
      final rightInset = m3e.spacing.lg;
      final bottomInset = m3e.spacing.lg;

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: DashboardSideSheetLayout(
              content: const SizedBox.expand(),
              sideSheet: Container(
                key: const Key('side_sheet'),
                color: Colors.blueGrey,
              ),
              sheetWidth: testSheetWidth,
              progress: 1,
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final sheetRect = tester.getRect(find.byKey(const Key('side_sheet')));
      final layoutRect = tester.getRect(find.byType(DashboardSideSheetLayout));

      expect(sheetRect.width, closeTo(testSheetWidth, 0.001));
      expect(sheetRect.right, closeTo(layoutRect.right - rightInset, 0.001));
      expect(sheetRect.bottom, closeTo(layoutRect.bottom - bottomInset, 0.001));
      expect(sheetRect.top, closeTo(layoutRect.top + topInset, 0.001));
    },
  );
}
