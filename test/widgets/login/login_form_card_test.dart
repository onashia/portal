import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/login/login_form_card.dart';

void main() {
  testWidgets('shows the sign-in title on the login screen', (tester) async {
    await tester.pumpWidget(
      _LoginFormCardHarness(authState: AuthState(status: AuthStatus.initial)),
    );

    expect(find.text('Sign in to your VRChat account'), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsNothing);
  });

  testWidgets('shows the generic 2FA title on the two-factor screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _LoginFormCardHarness(
        authState: AuthState(
          status: AuthStatus.requires2FA,
          requiresTwoFactorAuth: true,
        ),
      ),
    );

    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('Sign in to your VRChat account'), findsNothing);
  });
}

class _LoginFormCardHarness extends StatelessWidget {
  const _LoginFormCardHarness({required this.authState});

  final AuthState authState;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: LoginFormCard(
          authState: authState,
          formKey: GlobalKey<FormState>(),
          formBody: const SizedBox.shrink(),
          cardWidth: 400,
        ),
      ),
    );
  }
}
