import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/icon_sizes.dart';
import '../../providers/theme_provider.dart';

class ThemeModeToggleButton extends ConsumerWidget {
  const ThemeModeToggleButton({super.key, this.iconSize = IconSizes.xs});

  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    final isLightMode = mode == ThemeMode.light;

    return IconButton(
      icon: Icon(
        isLightMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
        size: iconSize,
      ),
      tooltip: isLightMode ? 'Dark Mode' : 'Light Mode',
      onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
    );
  }
}
