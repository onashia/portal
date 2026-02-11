import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../../constants/icon_sizes.dart';
import '../../utils/animation_constants.dart';

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

  double get _targetValue {
    if (_isPressed) return 1.0;
    if (_isHovered) return 0.5;
    return 0.0;
  }

  Color _interpolateBackgroundColor(double value) {
    if (value <= 0.5) {
      final t = value / 0.5;
      return Color.lerp(
        Colors.transparent,
        widget.hoverColor,
        t.clamp(0.0, 1.0),
      )!;
    } else {
      final t = (value - 0.5) / 0.5;
      return Color.lerp(
        widget.hoverColor,
        widget.pressedColor,
        t.clamp(0.0, 1.0),
      )!;
    }
  }

  Color _interpolateIconColor(double value) {
    if (widget.activeForegroundColor == null) {
      return widget.foregroundColor;
    }
    return Color.lerp(
      widget.foregroundColor,
      widget.activeForegroundColor!,
      value.clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
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
          child: SingleMotionBuilder(
            motion: AnimationConstants.standardEffectsFast,
            value: _targetValue,
            from: 0.0,
            builder: (context, value, child) {
              return Container(
                width: 46,
                height: 40,
                decoration: BoxDecoration(
                  color: _interpolateBackgroundColor(value),
                ),
                child: Icon(
                  widget.icon,
                  size: IconSizes.xxs,
                  color: _interpolateIconColor(value),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
