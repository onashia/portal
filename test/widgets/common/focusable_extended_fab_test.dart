import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/common/focusable_extended_fab.dart';

void main() {
  testWidgets('receives focus from a supplied focus node', (tester) async {
    final focusNode = FocusNode(debugLabel: 'focusable_extended_fab_test');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: FocusableExtendedFab(
              focusNode: focusNode,
              onPressed: () {},
              icon: const Icon(Icons.groups),
              label: const Text('Manage Groups'),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('does not build a tooltip when tooltip is omitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: FocusableExtendedFab(
              onPressed: () {},
              icon: const Icon(Icons.groups),
              label: const Text('Manage Groups'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('pressing Enter while focused invokes onPressed', (tester) async {
    final focusNode = FocusNode(debugLabel: 'focusable_extended_fab_enter');
    addTearDown(focusNode.dispose);
    var pressCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: FocusableExtendedFab(
              focusNode: focusNode,
              onPressed: () => pressCount += 1,
              icon: const Icon(Icons.groups),
              label: const Text('Manage Groups'),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(pressCount, 1);
  });

  testWidgets('pressing Space while focused invokes onPressed', (tester) async {
    final focusNode = FocusNode(debugLabel: 'focusable_extended_fab_space');
    addTearDown(focusNode.dispose);
    var pressCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: FocusableExtendedFab(
              focusNode: focusNode,
              onPressed: () => pressCount += 1,
              icon: const Icon(Icons.groups),
              label: const Text('Manage Groups'),
            ),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(pressCount, 1);
  });
}
