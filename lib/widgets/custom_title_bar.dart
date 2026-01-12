import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/theme_provider.dart';

class CustomTitleBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const CustomTitleBar({
    super.key,
    required this.title,
    this.actions,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Size get preferredSize => const Size.fromHeight(40);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    final bgColor = backgroundColor ?? 
        (isDark 
            ? theme.colorScheme.surface 
            : theme.colorScheme.surface);
    
    final fgColor = foregroundColor ?? 
        (isDark 
            ? theme.colorScheme.onSurface 
            : theme.colorScheme.onSurface);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: bgColor,
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: fgColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (actions != null) ...actions!,
          _WindowButtons(
            foregroundColor: fgColor,
            hoverColor: theme.hoverColor,
          ),
        ],
      ),
    );
  }
}

class _WindowButtons extends ConsumerWidget {
  final Color foregroundColor;
  final Color hoverColor;

  const _WindowButtons({
    required this.foregroundColor,
    required this.hoverColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 138,
      height: 40,
      child: Row(
        children: [
          _WindowButton(
            icon: Icons.remove,
            tooltip: 'Minimize',
            onPressed: () => windowManager.minimize(),
            foregroundColor: foregroundColor,
            hoverColor: hoverColor,
          ),
          _WindowButton(
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
          ),
          _WindowButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: () => windowManager.close(),
            foregroundColor: foregroundColor,
            hoverColor: Colors.red,
            isCloseButton: true,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color foregroundColor;
  final Color hoverColor;
  final bool isCloseButton;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.foregroundColor,
    required this.hoverColor,
    this.isCloseButton = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: widget.onPressed,
        onHover: (hovered) {
          setState(() {
            _isHovered = hovered;
          });
        },
        child: Container(
          width: 46,
          height: 40,
          decoration: BoxDecoration(
            color: _isHovered 
                ? (widget.isCloseButton 
                    ? Colors.red 
                    : widget.hoverColor.withOpacity(0.1))
                : null,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: widget.foregroundColor,
          ),
        ),
      ),
    );
  }
}
