import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:pinput/pinput.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class TwoFactorFormFields extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? errorMessage;
  final VoidCallback onSubmit;
  final Widget errorMessageWidget;
  final TwoFactorAuthType? method;
  final bool isSubmitting;

  const TwoFactorFormFields({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.errorMessage,
    required this.onSubmit,
    required this.errorMessageWidget,
    required this.method,
    required this.isSubmitting,
  });

  @override
  Widget build(BuildContext context) {
    final isErrorState = errorMessage != null;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final baseDecoration = BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: context.m3e.shapes.square.lg,
      border: Border.all(color: scheme.surfaceContainerHighest, width: 1),
    );
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
      decoration: baseDecoration,
    );
    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: baseDecoration.copyWith(
        border: Border.all(color: scheme.primary, width: 2),
      ),
    );
    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: baseDecoration.copyWith(
        border: Border.all(color: scheme.error, width: 2),
      ),
    );
    final helperText = switch (method) {
      TwoFactorAuthType.totp =>
        'Enter the 6-digit code from your authenticator app.',
      TwoFactorAuthType.emailOtp =>
        'Enter the verification code that VRChat sent to your email.',
      _ => 'Enter your verification code to continue.',
    };

    return Column(
      key: const ValueKey('twoFactorForm'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          helperText,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: context.m3e.spacing.lg),
        Pinput(
          controller: controller,
          focusNode: focusNode,
          enabled: !isSubmitting,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          length: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) {
            if (!isSubmitting) {
              onSubmit();
            }
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your verification code';
            }
            if (!RegExp(r'^\d{6}$').hasMatch(value)) {
              return 'Code must be exactly 6 digits';
            }
            return null;
          },
          forceErrorState: isErrorState,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          errorPinTheme: errorPinTheme,
          submittedPinTheme: defaultPinTheme,
          separatorBuilder: (_) => SizedBox(width: context.m3e.spacing.md),
        ),
        errorMessageWidget,
      ],
    );
  }
}
