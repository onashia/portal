import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import 'app_text_field.dart';

class PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueNotifier<bool> obscurePassword;
  final String? errorMessage;
  final Widget errorMessageWidget;

  const PasswordField({
    super.key,
    required this.controller,
    required this.focusNode,
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
              controller: controller,
              focusNode: focusNode,
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
