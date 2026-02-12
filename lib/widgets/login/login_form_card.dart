import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:motor/motor.dart';

import '../../providers/auth_provider.dart';
import '../../utils/animation_constants.dart';

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
    return SingleMotionBuilder(
      key: const ValueKey('loginCardAnimation'),
      motion: AnimationConstants.expressiveSpatialDefault,
      value: 1.0,
      from: 0.0,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(
            0,
            AnimationConstants.defaultSlideDistance * (1 - value),
          ),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
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
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.m3e.spacing.xl),
                        SingleMotionBuilder(
                          motion: AnimationConstants.expressiveSpatialDefault,
                          value: 1.0,
                          from: 0.0,
                          key: ValueKey(authState.requiresTwoFactorAuth),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(
                                0,
                                AnimationConstants.defaultSlideDistance *
                                    (1 - value),
                              ),
                              child: Opacity(
                                opacity: value.clamp(0.0, 1.0),
                                child: child,
                              ),
                            );
                          },
                          child: formBody,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
