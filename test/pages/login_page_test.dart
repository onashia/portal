import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';
import 'package:portal/pages/login_page.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/theme/app_theme.dart';

import '../test_helpers/auth_test_harness.dart';

void main() {
  testWidgets('username field receives initial focus on first load', (
    tester,
  ) async {
    final authNotifier = TestAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(() => authNotifier)],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginPage()),
      ),
    );

    await tester.pump();

    expect(find.byType(EditableText), findsNWidgets(2));
    final usernameField = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(usernameField.focusNode.hasFocus, isTrue);
  });

  testWidgets('transitioning to 2FA focuses the pinput field', (tester) async {
    final authNotifier = TestAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(() => authNotifier)],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginPage()),
      ),
    );

    await tester.pump();

    authNotifier.setData(
      const AuthState(
        status: AuthStatus.requires2FA,
        requiresTwoFactorAuth: true,
      ),
    );
    await tester.pump(); // Rebuild after state change.
    await tester.pump(); // Execute post-frame callback that requests focus.

    expect(find.byType(Pinput), findsOneWidget);
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isTrue);
  });

  testWidgets('initial 2FA state focuses the pinput field', (tester) async {
    final authNotifier = TestAuthNotifier(
      const AuthState(
        status: AuthStatus.requires2FA,
        requiresTwoFactorAuth: true,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(() => authNotifier)],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginPage()),
      ),
    );

    await tester.pump();

    expect(find.byType(Pinput), findsOneWidget);
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isTrue);
  });
}
