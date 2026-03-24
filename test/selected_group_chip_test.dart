import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/dashboard/selected_group_chip.dart';

import 'test_helpers/fake_vrchat_models.dart';

void main() {
  testWidgets('uses the shared boost copy for boosted chips without errors', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SelectedGroupChip(
              group: buildTestGroup(groupId: 'grp_alpha', name: 'Alpha'),
              hasError: false,
              isBoosted: true,
              isMonitoring: true,
              onToggleBoost: () {},
            ),
          ),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));

    expect(tooltip.message, 'Boost is active');
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byIcon(Icons.flash_on), findsOneWidget);
    expect(find.bySemanticsLabel('Alpha. Boost is active'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(SelectedGroupChip)),
      matchesSemantics(
        label: 'Alpha. Boost is active',
        isButton: true,
        hasTapAction: true,
      ),
    );

    semantics.dispose();
  });

  testWidgets(
    'renders error styling, tooltip, and semantics for errored chips',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SelectedGroupChip(
                group: buildTestGroup(groupId: 'grp_alpha', name: 'Alpha'),
                hasError: true,
                errorMessage: 'Failed to fetch instances',
                isBoosted: false,
                isMonitoring: true,
                onToggleBoost: () {},
              ),
            ),
          ),
        ),
      );

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(SelectedGroupChip),
          matching: find.byType(Material),
        ),
      );

      expect(tooltip.message, 'Failed to fetch instances');
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.flash_on), findsNothing);
      expect(material.color, AppTheme.lightTheme.colorScheme.errorContainer);
      expect(
        find.bySemanticsLabel('Alpha. Failed to fetch instances'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(SelectedGroupChip)),
        matchesSemantics(
          label: 'Alpha. Failed to fetch instances',
          isButton: true,
          hasTapAction: true,
        ),
      );

      semantics.dispose();
    },
  );

  testWidgets('keeps boost metadata visible when an errored chip is boosted', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SelectedGroupChip(
              group: buildTestGroup(groupId: 'grp_alpha', name: 'Alpha'),
              hasError: true,
              errorMessage: 'Failed to fetch instances',
              isBoosted: true,
              isMonitoring: true,
              onToggleBoost: () {},
            ),
          ),
        ),
      ),
    );

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(SelectedGroupChip),
        matching: find.byType(Material),
      ),
    );

    expect(tooltip.message, 'Failed to fetch instances. Boost is active');
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.flash_on), findsOneWidget);
    expect(material.color, AppTheme.lightTheme.colorScheme.errorContainer);
    expect(
      find.bySemanticsLabel(
        'Alpha. Failed to fetch instances. Boost is active',
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.byType(SelectedGroupChip)),
      matchesSemantics(
        label: 'Alpha. Failed to fetch instances. Boost is active',
        isButton: true,
        hasTapAction: true,
      ),
    );

    semantics.dispose();
  });
}
