import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class EventBadge extends StatelessWidget {
  final String label;

  const EventBadge({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.m3e.spacing.sm,
        vertical: context.m3e.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: context.m3e.shapes.round.xs,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
