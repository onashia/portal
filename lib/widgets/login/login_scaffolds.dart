import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../custom_title_bar.dart';
import 'login_theme_toggle.dart';

class LoginLoadingScaffold extends ConsumerWidget {
  const LoginLoadingScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [LoginThemeToggle()],
      ),
      body: Center(
        child: Transform.scale(
          scale: 2.0,
          child: const LoadingIndicatorM3E(
            variant: LoadingIndicatorM3EVariant.defaultStyle,
            semanticLabel: 'Loading portal',
          ),
        ),
      ),
    );
  }
}

class LoginErrorScaffold extends ConsumerWidget {
  final Object error;
  final StackTrace stack;

  const LoginErrorScaffold({
    super.key,
    required this.error,
    required this.stack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [LoginThemeToggle()],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(context.m3e.spacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              SizedBox(height: context.m3e.spacing.md),
              Text(
                'An error occurred',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
