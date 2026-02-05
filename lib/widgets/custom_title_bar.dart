import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:window_manager/window_manager.dart';

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
                      Icon(icon, size: 18, color: fgColor),
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
          _WindowButtons(foregroundColor: fgColor),
        ],
      ),
    );
  }
}

class _WindowButtons extends ConsumerWidget {
  final Color foregroundColor;

  const _WindowButtons({required this.foregroundColor});

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
          _WindowButton(
            icon: Icons.remove,
            tooltip: 'Minimize',
            onPressed: () => windowManager.minimize(),
            foregroundColor: foregroundColor,
            hoverColor: hoverColor,
            pressedColor: pressedColor,
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
            pressedColor: pressedColor,
          ),
          _WindowButton(
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

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color foregroundColor;
  final Color hoverColor;
  final Color pressedColor;
  final Color? activeForegroundColor;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.foregroundColor,
    required this.hoverColor,
    required this.pressedColor,
    this.activeForegroundColor,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isPressed
        ? widget.pressedColor
        : _isHovered
        ? widget.hoverColor
        : Colors.transparent;
    final iconColor =
        (_isHovered || _isPressed) && widget.activeForegroundColor != null
        ? widget.activeForegroundColor!
        : widget.foregroundColor;

    return Tooltip(
      message: widget.tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (hovered) {
            setState(() {
              _isHovered = hovered;
            });
          },
          onTapDown: (_) {
            setState(() {
              _isPressed = true;
            });
          },
          onTapCancel: () {
            setState(() {
              _isPressed = false;
            });
          },
          onTapUp: (_) {
            setState(() {
              _isPressed = false;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 46,
            height: 40,
            decoration: BoxDecoration(color: backgroundColor),
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}
