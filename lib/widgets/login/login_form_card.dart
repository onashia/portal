import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../providers/auth_provider.dart';
import '../animated_fade_slide.dart';

class LoginFormCard extends StatelessWidget {
  final AuthState authState;
  final GlobalKey<FormState> formKey;
  final Widget formBody;
  final double cardWidth;

  const LoginFormCard({
    super.key,
    required this.authState,
    required this.formKey,
    required this.formBody,
    required this.cardWidth,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedFadeSlide(
      key: const ValueKey('loginCardAnimation'),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cardWidth),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(context.m3e.spacing.xl * 2),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    authState.requiresTwoFactorAuth
                        ? 'Two-Factor Authentication'
                        : 'Sign in to your VRChat account',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: context.m3e.spacing.xl),
                  AnimatedFadeSlide(
                    key: ValueKey(authState.requiresTwoFactorAuth),
                    child: formBody,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
