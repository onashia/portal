import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/login/two_factor_form_fields.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

void main() {
  testWidgets('renders totp input without a method chooser', (tester) async {
    await tester.pumpWidget(
      _TwoFactorFormHarness(method: TwoFactorAuthType.totp),
    );

    expect(
      find.text('Enter the 6-digit code from your authenticator app.'),
      findsOne,
    );
    expect(find.byType(Pinput), findsOneWidget);
    expect(find.byType(SegmentedButton<TwoFactorAuthType>), findsNothing);
  });

  testWidgets('validates totp codes as six digits', (tester) async {
    await tester.pumpWidget(
      _TwoFactorFormHarness(method: TwoFactorAuthType.totp),
    );

    final pinput = tester.widget<Pinput>(find.byType(Pinput));
    expect(pinput.validator?.call('12345'), 'Code must be exactly 6 digits');
    expect(pinput.validator?.call('123456'), isNull);
  });

  testWidgets('renders email otp input using the shared pin widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TwoFactorFormHarness(method: TwoFactorAuthType.emailOtp),
    );

    expect(
      find.text('Enter the verification code that VRChat sent to your email.'),
      findsOneWidget,
    );
    expect(find.byType(Pinput), findsOneWidget);
  });

  testWidgets('validates email otp codes as six digits', (tester) async {
    await tester.pumpWidget(
      _TwoFactorFormHarness(method: TwoFactorAuthType.emailOtp),
    );

    final pinput = tester.widget<Pinput>(find.byType(Pinput));
    expect(pinput.validator?.call('12345'), 'Code must be exactly 6 digits');
    expect(pinput.validator?.call('123456'), isNull);
    expect(pinput.validator?.call(''), 'Please enter your verification code');
  });
}

class _TwoFactorFormHarness extends StatefulWidget {
  const _TwoFactorFormHarness({required this.method});

  final TwoFactorAuthType method;

  @override
  State<_TwoFactorFormHarness> createState() => _TwoFactorFormHarnessState();
}

class _TwoFactorFormHarnessState extends State<_TwoFactorFormHarness> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              TwoFactorFormFields(
                controller: _controller,
                focusNode: _focusNode,
                errorMessage: null,
                onSubmit: () {},
                errorMessageWidget: const SizedBox.shrink(),
                method: widget.method,
              ),
              TextButton(
                onPressed: () => _formKey.currentState!.validate(),
                child: const Text('Validate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
