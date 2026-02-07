import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import '../providers/group_calendar_provider.dart';
import '../providers/group_monitor_provider.dart';
import 'events/events_card_header.dart';
import 'events/events_card_states.dart';
import 'events/events_list_item.dart';

class GroupEventsCard extends ConsumerWidget {
  final String userId;

  const GroupEventsCard({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendarState = ref.watch(groupCalendarProvider(userId));
    final monitorState = ref.watch(groupMonitorProvider(userId));
    final scheme = Theme.of(context).colorScheme;
    final cardTheme = Theme.of(context).cardTheme;
    final baseShape =
        cardTheme.shape as RoundedRectangleBorder? ??
        RoundedRectangleBorder(borderRadius: context.m3e.shapes.round.md);
    final outlineColor = scheme.outlineVariant.withValues(alpha: 0.4);
    final todayLabel = _formatDateLabel(DateTime.now());

    return Card(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: baseShape.copyWith(side: BorderSide(color: outlineColor)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EventsCardHeader(todayLabel: todayLabel),
            SizedBox(height: context.m3e.spacing.md),
            Expanded(
              child: _buildContent(context, calendarState, monitorState),
            ),
            if (calendarState.groupErrors.isNotEmpty) ...[
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                'Some groups failed to load (${calendarState.groupErrors.length})',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    GroupCalendarState calendarState,
    GroupMonitorState monitorState,
  ) {
    if (monitorState.selectedGroupIds.isEmpty) {
      return const EventsEmptyState(
        icon: Icons.event_busy,
        title: 'No Groups Selected',
        message: 'Select groups in Group Monitoring to see events.',
      );
    }

    if (calendarState.isLoading && calendarState.todayEvents.isEmpty) {
      return const EventsLoadingState();
    }

    if (calendarState.todayEvents.isEmpty) {
      return const EventsEmptyState(
        icon: Icons.event_available,
        title: 'No Events Today',
        message: 'Your groups have nothing scheduled for today.',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: calendarState.todayEvents.length,
      itemBuilder: (context, index) {
        final event = calendarState.todayEvents[index];
        final isLast = index == calendarState.todayEvents.length - 1;
        return EventsListItem(
          event: event,
          isFirst: index == 0,
          isLast: isLast,
        );
      },
    );
  }

  String _formatDateLabel(DateTime date) {
    final local = date.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[local.month - 1];
    return '$month ${local.day}, ${local.year}';
  }
}
