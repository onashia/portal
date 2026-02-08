import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class GroupsLoadingState extends StatelessWidget {
  const GroupsLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicatorM3E(
              variant: LoadingIndicatorM3EVariant.defaultStyle,
              semanticLabel: 'Loading available groups',
            ),
            SizedBox(height: context.m3e.spacing.lg),
            Text(
              'Loading available groups...',
              style: context.m3e.typography.base.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
