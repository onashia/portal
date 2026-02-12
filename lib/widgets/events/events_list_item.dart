import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/ui_constants.dart';
import '../../models/group_calendar_event.dart';
import '../../utils/group_utils.dart';
import '../group_selection/group_avatar.dart';
import 'event_badge.dart';
import 'timeline_widgets.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final group = event.group;
    final badgeLabel = _buildBadgeLabel(event.event);
    final avatarSize = UiConstants.groupAvatarLg;
    final groupName = group?.name ?? _fallbackGroupName(event.groupId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TimelineRail(
              label: DateFormat.jm().format(event.event.startsAt),
              height: avatarSize,
              isFirst: isFirst,
              isLast: isLast,
            ),
            SizedBox(width: context.m3e.spacing.sm),
            GroupAvatar(
              group: group ?? LimitedUserGroups(),
              size: UiConstants.groupAvatarLg,
              borderRadius: context.m3e.shapes.square.sm,
            ),
            SizedBox(width: context.m3e.spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  SizedBox(height: context.m3e.spacing.xs),
                  Text(
                    event.event.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            SizedBox(width: context.m3e.spacing.sm),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: EventBadge(label: badgeLabel),
              ),
            ),
          ],
        ),
        if (!isLast) TimelineConnector(height: context.m3e.spacing.sm),
      ],
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
