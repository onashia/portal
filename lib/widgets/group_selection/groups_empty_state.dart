import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class GroupsEmptyState extends StatelessWidget {
  final bool hasAnyGroups;
  final bool isSearching;
  final String searchQuery;

  const GroupsEmptyState({
    super.key,
    required this.hasAnyGroups,
    required this.isSearching,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final showSecondaryLine = !hasAnyGroups && !isSearching;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off, size: 64, color: scheme.onSurfaceVariant),
            SizedBox(height: context.m3e.spacing.lg),
            Text(
              isSearching
                  ? 'No groups match "$searchQuery"'
                  : 'No groups found',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (showSecondaryLine) ...[
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                'You are not a member of any groups',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
