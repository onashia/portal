import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../providers/auth_provider.dart';

class LoginSubmitButton extends StatelessWidget {
  final AuthState authState;
  final VoidCallback onPressed;

  const LoginSubmitButton({
    super.key,
    required this.authState,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isLoading = authState.isLoading;
    final buttonText = authState.status == AuthStatus.requiresEmailVerification
        ? 'Retry Login'
        : authState.requiresTwoFactorAuth
        ? 'Verify'
        : 'Sign In';

    return ButtonM3E(
      onPressed: isLoading ? null : onPressed,
      label: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : Text(buttonText),
      style: ButtonM3EStyle.filled,
      size: ButtonM3ESize.md,
      shape: ButtonM3EShape.square,
    );
  }
}
