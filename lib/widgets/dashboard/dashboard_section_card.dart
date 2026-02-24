import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class DashboardSectionCard extends StatelessWidget {
  const DashboardSectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardTheme = Theme.of(context).cardTheme;
    final baseShape =
        cardTheme.shape as RoundedRectangleBorder? ??
        RoundedRectangleBorder(borderRadius: context.m3e.shapes.round.md);
    final outlineColor = scheme.outlineVariant.withValues(alpha: 0.4);

    return Card(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: baseShape.copyWith(side: BorderSide(color: outlineColor)),
      child: Padding(
        padding: padding ?? EdgeInsets.all(context.m3e.spacing.xl),
        child: child,
      ),
    );
  }
}
