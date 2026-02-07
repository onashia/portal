import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import '../../providers/group_monitor_state.dart';

class GroupInstancesEmptyState extends StatelessWidget {
  final GroupMonitorState state;

  const GroupInstancesEmptyState({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.selectedGroupIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.group_off,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(height: context.m3e.spacing.md),
              Text(
                'No Groups Selected',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                'Select groups to monitor for new instances',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hasErrors = state.groupErrors.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasErrors ? Icons.error_outline : Icons.wifi_off,
              size: 64,
              color: hasErrors
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: context.m3e.spacing.md),
            Text(
              state.isMonitoring ? 'No Instances Open' : 'Monitoring Paused',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: context.m3e.spacing.sm),
            Text(
              state.isMonitoring
                  ? 'No instances are currently open for your selected groups'
                  : 'Start monitoring to see open instances',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
