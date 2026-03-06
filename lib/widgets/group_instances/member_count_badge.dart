import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class MemberCountBadge extends StatelessWidget {
  final int userCount;

  const MemberCountBadge({super.key, required this.userCount});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.m3e.spacing.md,
        vertical: context.m3e.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: context.m3e.shapes.round.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: context.m3e.spacing.xs,
        children: [
          Icon(Icons.people, size: 16, color: scheme.onSecondaryContainer),
          Text(
            userCount.toString(),
            style: textTheme.labelMedium?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
