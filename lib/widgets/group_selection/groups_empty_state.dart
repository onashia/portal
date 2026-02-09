import 'package:flutter/material.dart';

import '../common/empty_state.dart';

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
    final showSecondaryLine = !hasAnyGroups && !isSearching;
    final message = showSecondaryLine
        ? 'You are not a member of any groups'
        : null;
    final title = isSearching
        ? 'No groups match "$searchQuery"'
        : 'No groups found';

    return EmptyState(
      icon: Icons.group_off,
      title: title,
      message: message,
      messageStyle: textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
