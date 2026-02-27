import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../models/group_calendar_event.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/group_utils.dart';
import 'event_badge.dart';
import 'timeline_list_item.dart';

class EventsListItem extends StatelessWidget {
  final GroupCalendarEvent event;
  final bool isFirst;
  final bool isLast;

  const EventsListItem({
    super.key,
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final group = event.group;
    final badgeLabel = _buildBadgeLabel(event.event);
    final groupName = group?.name ?? _fallbackGroupName(event.groupId);
    final timeLabel = DateTimeUtils.formatLocalJm(event.event.startsAt);

    return TimelineListItem(
      timeLabel: timeLabel,
      group: group,
      groupName: groupName,
      subtitle: event.event.title,
      isFirst: isFirst,
      isLast: isLast,
      trailing: Flexible(
        fit: FlexFit.loose,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: EventBadge(label: badgeLabel),
        ),
      ),
    );
  }

  String _buildBadgeLabel(CalendarEvent event) {
    final interested = event.interestedUserCount;
    if (interested != null && interested > 0) {
      return '$interested interested';
    }

    final rawCategory = event.category.value.replaceAll('_', ' ');
    if (rawCategory.isEmpty) {
      return 'Other';
    }
    return rawCategory[0].toUpperCase() + rawCategory.substring(1);
  }

  String _fallbackGroupName(String groupId) {
    return GroupUtils.getShortGroupId(groupId);
  }
}
