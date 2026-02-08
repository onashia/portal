import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../constants/icon_sizes.dart';
import '../common/empty_state.dart';
import '../common/loading_state.dart';
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
      body: const LoadingState(semanticLabel: 'Loading portal', scale: 2.0),
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [LoginThemeToggle()],
      ),
      body: EmptyState(
        icon: Icons.error_outline,
        title: 'An error occurred',
        message: error.toString(),
        iconSize: IconSizes.xl,
        iconColor: scheme.error,
        titleStyle: Theme.of(context).textTheme.headlineMedium,
        padding: EdgeInsets.all(context.m3e.spacing.lg),
      ),
    );
  }
}
