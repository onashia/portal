import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../inputs/app_text_field.dart';
import '../inputs/password_field.dart';

class LoginFormFields extends StatelessWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode usernameFocusNode;
  final FocusNode passwordFocusNode;
  final ValueNotifier<bool> obscurePassword;
  final String? errorMessage;
  final Widget errorMessageWidget;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  const LoginFormFields({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.usernameFocusNode,
    required this.passwordFocusNode,
    required this.obscurePassword,
    required this.errorMessage,
    required this.errorMessageWidget,
    required this.isSubmitting,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('loginForm'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: usernameController,
          focusNode: usernameFocusNode,
          onFieldSubmitted: (_) {
            if (!isSubmitting) {
              passwordFocusNode.requestFocus();
            }
          },
          enabled: !isSubmitting,
          decoration: const InputDecoration(
            labelText: 'Username',
            hintText: 'Enter your username',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your username';
            }
            return null;
          },
        ),
        SizedBox(height: context.m3e.spacing.md),
        PasswordField(
          controller: passwordController,
          focusNode: passwordFocusNode,
          obscurePassword: obscurePassword,
          errorMessage: errorMessage,
          errorMessageWidget: errorMessageWidget,
          enabled: !isSubmitting,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            if (!isSubmitting) {
              onSubmit();
            }
          },
        ),
        SizedBox(height: context.m3e.spacing.lg),
      ],
    );
  }
}
