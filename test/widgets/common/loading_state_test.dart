import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/common/loading_state.dart';

void main() {
  testWidgets('forwards semanticLabel to the loading indicator', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: LoadingState(semanticLabel: 'Loading events'),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Loading events'), findsOneWidget);
    semantics.dispose();
  });
}
