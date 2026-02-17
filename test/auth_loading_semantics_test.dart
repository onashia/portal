import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/login/login_submit_button.dart';

void main() {
  testWidgets('shows loading indicator when auth status is loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LoginSubmitButton(
            authState: const AuthState(status: AuthStatus.loading),
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
  });

  testWidgets('shows verify text for non-loading 2FA state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LoginSubmitButton(
            authState: const AuthState(
              status: AuthStatus.requires2FA,
              requiresTwoFactorAuth: true,
            ),
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('Verify'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows retry text for email verification state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: LoginSubmitButton(
            authState: const AuthState(
              status: AuthStatus.requiresEmailVerification,
            ),
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('Retry Login'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
