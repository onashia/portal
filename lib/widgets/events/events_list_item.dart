import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/ui_constants.dart';
import '../../models/group_calendar_event.dart';
import '../../utils/group_utils.dart';
import '../cached_image.dart';
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
    final rowHeight = avatarSize;
    final avatarRadius = context.m3e.shapes.square.sm;
    final eventImageUrl = event.event.imageUrl;
    final groupImageUrl = group?.iconUrl;
    final imageUrl = (eventImageUrl?.isNotEmpty ?? false)
        ? eventImageUrl
        : groupImageUrl;
    final hasImage = imageUrl?.isNotEmpty ?? false;
    final groupName = group?.name ?? _fallbackGroupName(event.groupId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TimelineRail(
              label: _formatTime(event.event.startsAt),
              height: rowHeight,
              isFirst: isFirst,
              isLast: isLast,
            ),
            SizedBox(width: context.m3e.spacing.sm),
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                borderRadius: avatarRadius,
                color: hasImage
                    ? null
                    : GroupUtils.getAvatarColor(group ?? LimitedUserGroups()),
              ),
              child: ClipRRect(
                borderRadius: avatarRadius,
                clipBehavior: Clip.antiAlias,
                child: CachedImage(
                  imageUrl: imageUrl ?? '',
                  width: avatarSize,
                  height: avatarSize,
                  fit: BoxFit.cover,
                  showLoadingIndicator: false,
                  fallbackWidget: hasImage
                      ? null
                      : Center(
                          child: Text(
                            GroupUtils.getInitials(
                              group ?? LimitedUserGroups(),
                            ),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                ),
              ),
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

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final isAm = hour < 12;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = isAm ? 'AM' : 'PM';
    return '$hour12:$minute $suffix';
  }

  String _fallbackGroupName(String groupId) {
    if (groupId.length <= 8) {
      return groupId;
    }
    return groupId.substring(0, 8);
  }
}
