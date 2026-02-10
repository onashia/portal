import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/icon_sizes.dart';
import '../../providers/theme_provider.dart';

class LoginThemeToggle extends ConsumerWidget {
  const LoginThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: Icon(
        ref.watch(themeProvider) == ThemeMode.light
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined,
        size: IconSizes.xs,
      ),
      tooltip: ref.watch(themeProvider) == ThemeMode.light
          ? 'Dark Mode'
          : 'Light Mode',
      onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
    );
  }
}
