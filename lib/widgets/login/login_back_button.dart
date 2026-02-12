import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class LoginBackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const LoginBackButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ButtonM3E(
      onPressed: onPressed,
      label: const Text('Back to login'),
      style: ButtonM3EStyle.text,
      size: ButtonM3ESize.sm,
      shape: ButtonM3EShape.square,
    );
  }
}
