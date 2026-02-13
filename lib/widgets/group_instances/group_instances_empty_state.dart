import 'package:flutter/material.dart';
import '../common/empty_state.dart';

class GroupInstancesEmptyState extends StatelessWidget {
  final bool hasSelectedGroups;
  final bool hasErrors;

  const GroupInstancesEmptyState({
    super.key,
    required this.hasSelectedGroups,
    required this.hasErrors,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasSelectedGroups) {
      return const EmptyState(
        icon: Icons.group_off,
        title: 'No Groups Selected',
        message: 'Select groups to monitor for new instances',
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return EmptyState(
      icon: hasErrors ? Icons.error_outline : Icons.wifi_off,
      title: 'No Instances Open',
      message: 'No instances are currently open for your selected groups',
      iconColor: hasErrors ? scheme.error : null,
    );
  }
}
