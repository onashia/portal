import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../constants/ui_constants.dart';
import '../group_events_card.dart';
import 'dashboard_group_monitoring_section.dart';

class DashboardCards extends ConsumerWidget {
  final String userId;
  final bool canShowSideBySide;

  const DashboardCards({
    super.key,
    required this.userId,
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
            child: DashboardGroupMonitoringSection(userId: userId),
          ),
          SizedBox(width: spacing),
          Expanded(flex: 2, child: GroupEventsCard(userId: userId)),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final eventsCardHeight = UiConstants.dashboardStackedEventsCardHeight;
        final minMonitoringHeight =
            UiConstants.dashboardMinMonitoringCardHeight;
        final monitoringCardHeight =
            (constraints.maxHeight - eventsCardHeight - spacing).clamp(
              minMonitoringHeight,
              double.infinity,
            );

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                SizedBox(
                  height: monitoringCardHeight,
                  child: DashboardGroupMonitoringSection(userId: userId),
                ),
                SizedBox(height: spacing),
                SizedBox(
                  height: eventsCardHeight,
                  child: GroupEventsCard(userId: userId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
