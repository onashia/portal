import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:motor/motor.dart';

import '../../utils/animation_constants.dart';

class LoginErrorMessage extends StatelessWidget {
  final String? message;

  const LoginErrorMessage(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: AnimationConstants.expressiveSpatialDefault,
      value: message != null ? 1.0 : 0.0,
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Opacity(
        opacity: message != null ? 1.0 : 0.0,
        child: Padding(
          padding: EdgeInsets.only(top: context.m3e.spacing.sm),
          child: Text(
            message ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}
