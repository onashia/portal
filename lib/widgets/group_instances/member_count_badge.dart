import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class MemberCountBadge extends StatelessWidget {
  final int userCount;

  const MemberCountBadge({super.key, required this.userCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.m3e.spacing.md,
        vertical: context.m3e.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: context.m3e.shapes.round.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          SizedBox(width: context.m3e.spacing.xs),
          Text(
            userCount.toString(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
