import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/icon_sizes.dart';
import 'window/window_button_bar.dart';

class CustomTitleBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final IconData? icon;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool showBranding;

  const CustomTitleBar({
    super.key,
    required this.title,
    this.icon,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
    this.showBranding = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final bgColor = backgroundColor ?? theme.colorScheme.surface;

    final fgColor = foregroundColor ?? theme.colorScheme.onSurface;

    return Container(
      height: 40,
      decoration: BoxDecoration(color: bgColor),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.m3e.spacing.md,
                ),
                child: Row(
                  children: [
                    if (showBranding) ...[
                      Icon(icon, size: IconSizes.xs, color: fgColor),
                      SizedBox(width: context.m3e.spacing.sm),
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: fgColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (actions != null) ...actions!,
          WindowButtonBar(foregroundColor: fgColor),
        ],
      ),
    );
  }
}
