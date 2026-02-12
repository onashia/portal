import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../constants/icon_sizes.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final double iconSize;
  final Color? iconColor;
  final TextStyle? titleStyle;
  final TextStyle? messageStyle;
  final EdgeInsetsGeometry? padding;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.iconSize = IconSizes.lg,
    this.iconColor,
    this.titleStyle,
    this.messageStyle,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? scheme.onSurfaceVariant;
    final effectiveTitleStyle =
        titleStyle ?? context.m3e.typography.base.titleMedium;
    final effectiveMessageStyle =
        messageStyle ??
        context.m3e.typography.base.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        );

    return Center(
      child: Padding(
        padding: padding ?? EdgeInsets.all(context.m3e.spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: effectiveIconColor),
            SizedBox(height: context.m3e.spacing.lg),
            Text(title, style: effectiveTitleStyle),
            if (message != null) ...[
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: effectiveMessageStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
