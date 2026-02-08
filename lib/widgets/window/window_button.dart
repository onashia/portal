import 'package:flutter/material.dart';

class WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color foregroundColor;
  final Color hoverColor;
  final Color pressedColor;
  final Color? activeForegroundColor;

  const WindowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.foregroundColor,
    required this.hoverColor,
    required this.pressedColor,
    this.activeForegroundColor,
  });

  @override
  State<WindowButton> createState() => WindowButtonState();
}

class WindowButtonState extends State<WindowButton> {
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
