import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../providers/group_monitor_provider.dart';
import '../group_events_card.dart';
import 'dashboard_group_monitoring_section.dart';

class DashboardCards extends ConsumerWidget {
  final String userId;
  final GroupMonitorState monitorState;
  final List<LimitedUserGroups> selectedGroups;
  final bool canShowSideBySide;

  const DashboardCards({
    super.key,
    required this.userId,
    required this.monitorState,
    required this.selectedGroups,
    required this.canShowSideBySide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.m3e.spacing.lg;

    if (canShowSideBySide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: DashboardGroupMonitoringSection(
              userId: userId,
              monitorState: monitorState,
              selectedGroups: selectedGroups,
            ),
          ),
          SizedBox(width: spacing),
          Expanded(flex: 2, child: GroupEventsCard(userId: userId)),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  Expanded(
                    child: DashboardGroupMonitoringSection(
                      userId: userId,
                      monitorState: monitorState,
                      selectedGroups: selectedGroups,
                    ),
                  ),
                  SizedBox(height: spacing),
                  SizedBox(height: 320, child: GroupEventsCard(userId: userId)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
