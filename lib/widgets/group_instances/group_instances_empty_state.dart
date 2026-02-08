import 'package:flutter/material.dart';

import '../../constants/icon_sizes.dart';
import '../../providers/group_monitor_state.dart';
import '../common/empty_state.dart';

class GroupInstancesEmptyState extends StatelessWidget {
  final GroupMonitorState state;

  const GroupInstancesEmptyState({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.selectedGroupIds.isEmpty) {
      return const EmptyState(
        icon: Icons.group_off,
        title: 'No Groups Selected',
        message: 'Select groups to monitor for new instances',
        iconSize: IconSizes.xl,
      );
    }

    final hasErrors = state.groupErrors.isNotEmpty;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return EmptyState(
      icon: hasErrors ? Icons.error_outline : Icons.wifi_off,
      title: state.isMonitoring ? 'No Instances Open' : 'Monitoring Paused',
      message: state.isMonitoring
          ? 'No instances are currently open for your selected groups'
          : 'Start monitoring to see open instances',
      iconSize: IconSizes.xl,
      iconColor: hasErrors ? scheme.error : null,
      titleStyle: textTheme.titleLarge,
    );
  }
}
