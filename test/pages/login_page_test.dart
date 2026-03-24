import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';
import 'package:portal/pages/login_page.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/inputs/app_text_field.dart';
import 'package:portal/widgets/inputs/password_field.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../test_helpers/auth_test_harness.dart';

class _RecordingAuthNotifier extends TestAuthNotifier {
  _RecordingAuthNotifier(super.initialState);

  String? submittedUsername;
  String? submittedPassword;
  String? submittedTwoFactorCode;
  int loginCallCount = 0;
  int verify2FACallCount = 0;

  @override
  Future<void> login(String username, String password) async {
    loginCallCount += 1;
    submittedUsername = username;
    submittedPassword = password;
    state = const AsyncData(AuthState(status: AuthStatus.loading));
  }

  @override
  Future<void> verify2FA(String code) async {
    verify2FACallCount += 1;
    submittedTwoFactorCode = code;
    state = AsyncData(_loadingTwoFactorState());
  }
}

AuthState _loadingTwoFactorState() {
  return const AuthState(
    status: AuthStatus.loading,
    requiresTwoFactorAuth: true,
    selectedTwoFactorMethod: TwoFactorAuthType.totp,
  );
}

Future<void> _pumpLoginPage(
  WidgetTester tester,
  AuthNotifier authNotifier,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authProvider.overrideWith(() => authNotifier)],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const LoginPage()),
    ),
  );

  await tester.pump();
}

void main() {
  testWidgets('username field receives initial focus on first load', (
    tester,
  ) async {
    final authNotifier = TestAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await _pumpLoginPage(tester, authNotifier);

    expect(find.byType(EditableText), findsNWidgets(2));
    final usernameField = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    expect(usernameField.focusNode.hasFocus, isTrue);
  });

  testWidgets('enter on username field moves focus to password', (
    tester,
  ) async {
    final authNotifier = TestAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await _pumpLoginPage(tester, authNotifier);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.showKeyboard(fields.first);
    await tester.enterText(fields.first, 'alice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final passwordField = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    expect(passwordField.focusNode.hasFocus, isTrue);
  });

  testWidgets('enter on password field submits login', (tester) async {
    final authNotifier = _RecordingAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await _pumpLoginPage(tester, authNotifier);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.first, 'alice');
    await tester.enterText(fields.last, 'secret');
    await tester.showKeyboard(fields.last);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(authNotifier.loginCallCount, 1);
    expect(authNotifier.submittedUsername, 'alice');
    expect(authNotifier.submittedPassword, 'secret');
  });

  testWidgets('enter on password field does not resubmit while loading', (
    tester,
  ) async {
    final authNotifier = _RecordingAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await _pumpLoginPage(tester, authNotifier);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.first, 'alice');
    await tester.enterText(fields.last, 'secret');
    await tester.showKeyboard(fields.last);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(authNotifier.loginCallCount, 1);

    final passwordField = tester.widget<TextFormField>(fields.last);
    expect(passwordField.enabled, isFalse);

    final passwordAppField = tester.widget<AppTextField>(
      find.byType(AppTextField).last,
    );
    passwordAppField.onFieldSubmitted?.call('secret');
    await tester.pump();

    expect(authNotifier.loginCallCount, 1);
  });

  testWidgets('failed login retry refocuses password field', (tester) async {
    final authNotifier = _RecordingAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await _pumpLoginPage(tester, authNotifier);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.first, 'alice');
    await tester.enterText(fields.last, 'secret');
    await tester.showKeyboard(fields.last);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    authNotifier.setData(
      const AuthState(
        status: AuthStatus.error,
        errorMessage: 'Login failed: Invalid username or password',
      ),
    );
    await tester.pump();
    await tester.pump();

    final passwordField = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    expect(passwordField.focusNode.hasFocus, isTrue);
  });

  testWidgets('email verification retry refocuses password field', (
    tester,
  ) async {
    final authNotifier = _RecordingAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await _pumpLoginPage(tester, authNotifier);

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));

    await tester.enterText(fields.first, 'alice');
    await tester.enterText(fields.last, 'secret');
    await tester.showKeyboard(fields.last);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    authNotifier.setData(
      const AuthState(
        status: AuthStatus.requiresEmailVerification,
        errorMessage: 'Login failed: Check your email for verification',
      ),
    );
    await tester.pump();
    await tester.pump();

    final passwordField = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    expect(passwordField.focusNode.hasFocus, isTrue);
  });

  testWidgets('loading login state disables fields and password toggle', (
    tester,
  ) async {
    final authNotifier = TestAuthNotifier(
      const AuthState(status: AuthStatus.loading),
    );

    await _pumpLoginPage(tester, authNotifier);

    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields, hasLength(2));
    expect(fields.every((field) => field.enabled == false), isTrue);

    final visibilityButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byType(PasswordField),
        matching: find.byType(IconButton),
      ),
    );
    expect(visibilityButton.onPressed, isNull);
  });

  testWidgets('transitioning to 2FA focuses the pinput field', (tester) async {
    final authNotifier = TestAuthNotifier(
      const AuthState(status: AuthStatus.initial),
    );

    await _pumpLoginPage(tester, authNotifier);

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

    await _pumpLoginPage(tester, authNotifier);

    expect(find.byType(Pinput), findsOneWidget);
    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isTrue);
  });

  testWidgets('enter on 2FA field does not resubmit while loading', (
    tester,
  ) async {
    final authNotifier = _RecordingAuthNotifier(
      const AuthState(
        status: AuthStatus.requires2FA,
        requiresTwoFactorAuth: true,
        selectedTwoFactorMethod: TwoFactorAuthType.totp,
      ),
    );

    await _pumpLoginPage(tester, authNotifier);

    await tester.enterText(find.byType(EditableText), '123456');
    await tester.pump();

    final activePinput = tester.widget<Pinput>(find.byType(Pinput));
    activePinput.onSubmitted?.call('123456');
    await tester.pump();

    expect(authNotifier.verify2FACallCount, 1);
    expect(authNotifier.submittedTwoFactorCode, '123456');

    final pinput = tester.widget<Pinput>(find.byType(Pinput));
    expect(pinput.enabled, isFalse);

    pinput.onSubmitted?.call('123456');
    await tester.pump();

    expect(authNotifier.verify2FACallCount, 1);
  });

  testWidgets('failed 2FA retry refocuses the pinput field', (tester) async {
    final authNotifier = _RecordingAuthNotifier(
      const AuthState(
        status: AuthStatus.requires2FA,
        requiresTwoFactorAuth: true,
        selectedTwoFactorMethod: TwoFactorAuthType.totp,
      ),
    );

    await _pumpLoginPage(tester, authNotifier);

    await tester.enterText(find.byType(EditableText), '123456');
    await tester.pump();

    final activePinput = tester.widget<Pinput>(find.byType(Pinput));
    activePinput.onSubmitted?.call('123456');
    await tester.pump();

    authNotifier.setData(
      const AuthState(
        status: AuthStatus.requires2FA,
        requiresTwoFactorAuth: true,
        selectedTwoFactorMethod: TwoFactorAuthType.totp,
        errorMessage: '2FA verification failed: Invalid code',
      ),
    );
    await tester.pump();
    await tester.pump();

    final editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isTrue);
  });

  testWidgets('loading 2FA state disables pinput', (tester) async {
    final authNotifier = TestAuthNotifier(_loadingTwoFactorState());

    await _pumpLoginPage(tester, authNotifier);

    final pinput = tester.widget<Pinput>(find.byType(Pinput));
    expect(pinput.enabled, isFalse);
  });
}
