import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'window_button.dart';

class WindowButtonBar extends ConsumerWidget {
  final Color foregroundColor;

  const WindowButtonBar({super.key, required this.foregroundColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hoverColor = scheme.onSurface.withValues(alpha: 0.08);
    final pressedColor = scheme.onSurface.withValues(alpha: 0.12);
    final closeHoverColor = scheme.errorContainer;
    final closePressedColor = scheme.error.withValues(alpha: 0.2);

    return SizedBox(
      width: 138,
      height: 40,
      child: Row(
        children: [
          WindowButton(
            icon: Icons.remove,
            tooltip: 'Minimize',
            onPressed: () => windowManager.minimize(),
            foregroundColor: foregroundColor,
            hoverColor: hoverColor,
            pressedColor: pressedColor,
          ),
          WindowButton(
            icon: Icons.check_box_outline_blank,
            tooltip: 'Maximize',
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            foregroundColor: foregroundColor,
            hoverColor: hoverColor,
            pressedColor: pressedColor,
          ),
          WindowButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () => windowManager.close(),
            foregroundColor: foregroundColor,
            hoverColor: closeHoverColor,
            pressedColor: closePressedColor,
            activeForegroundColor: scheme.onErrorContainer,
          ),
        ],
      ),
    );
  }
}
