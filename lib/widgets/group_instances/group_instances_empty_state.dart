import 'package:flutter/material.dart';
import '../common/empty_state.dart';

enum GroupInstancesEmptyStateVariant {
  noGroupsSelected,
  unableToLoadInstances,
  noInstancesOpen,
}

class GroupInstancesEmptyState extends StatelessWidget {
  final GroupInstancesEmptyStateVariant variant;

  const GroupInstancesEmptyState({super.key, required this.variant});

  @override
  Widget build(BuildContext context) {
    if (variant == GroupInstancesEmptyStateVariant.noGroupsSelected) {
      return const EmptyState(
        icon: Icons.group_off,
        title: 'No Groups Selected',
        message: 'Select groups to monitor for new instances',
      );
    }

    final scheme = Theme.of(context).colorScheme;

    if (variant == GroupInstancesEmptyStateVariant.unableToLoadInstances) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Unable to Load Instances',
        message: 'Could not refresh group instances. Try manual refresh.',
        iconColor: scheme.error,
      );
    }

    return const EmptyState(
      icon: Icons.wifi_off,
      title: 'No Instances Open',
      message: 'No instances are currently open for your selected groups',
    );
  }
}
