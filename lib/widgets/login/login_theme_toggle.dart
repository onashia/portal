import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../providers/theme_provider.dart';

class LoginThemeToggle extends ConsumerWidget {
  const LoginThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButtonM3E(
      icon: Icon(
        ref.watch(themeProvider) == ThemeMode.light
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined,
      ),
      tooltip: ref.watch(themeProvider) == ThemeMode.light
          ? 'Dark Mode'
          : 'Light Mode',
      onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
      variant: IconButtonM3EVariant.standard,
      size: IconButtonM3ESize.sm,
      shape: IconButtonM3EShapeVariant.round,
    );
  }
}
