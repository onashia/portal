import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../inputs/app_text_field.dart';

class LoginFormFields extends StatelessWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode usernameFocusNode;
  final FocusNode passwordFocusNode;
  final ValueNotifier<bool> obscurePassword;
  final String? errorMessage;
  final Widget errorMessageWidget;

  const LoginFormFields({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.usernameFocusNode,
    required this.passwordFocusNode,
    required this.obscurePassword,
    required this.errorMessage,
    required this.errorMessageWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('loginForm'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextFormField(
          controller: usernameController,
          focusNode: usernameFocusNode,
          onFieldSubmitted: (_) => passwordFocusNode.requestFocus(),
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
        _PasswordField(
          passwordController: passwordController,
          passwordFocusNode: passwordFocusNode,
          obscurePassword: obscurePassword,
          errorMessage: errorMessage,
          errorMessageWidget: errorMessageWidget,
        ),
        SizedBox(height: context.m3e.spacing.lg),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final ValueNotifier<bool> obscurePassword;
  final String? errorMessage;
  final Widget errorMessageWidget;

  const _PasswordField({
    required this.passwordController,
    required this.passwordFocusNode,
    required this.obscurePassword,
    required this.errorMessage,
    required this.errorMessageWidget,
  });

  @override
  Widget build(BuildContext context) {
    final isErrorState = errorMessage != null;

    return ValueListenableBuilder(
      valueListenable: obscurePassword,
      builder: (context, obscure, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextFormField(
              controller: passwordController,
              focusNode: passwordFocusNode,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButtonM3E(
                  icon: const Icon(Icons.visibility),
                  selectedIcon: const Icon(Icons.visibility_off),
                  isSelected: obscure,
                  onPressed: () => obscurePassword.value = !obscure,
                  tooltip: obscure ? 'Show password' : 'Hide password',
                  variant: IconButtonM3EVariant.standard,
                  size: IconButtonM3ESize.sm,
                  shape: IconButtonM3EShapeVariant.round,
                ),
                errorText: isErrorState ? errorMessage : null,
                errorStyle: isErrorState
                    ? const TextStyle(height: 0, fontSize: 0)
                    : null,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
            errorMessageWidget,
          ],
        );
      },
    );
  }
}
