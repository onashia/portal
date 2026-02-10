import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../../constants/ui_constants.dart';
import '../../models/group_instance_with_group.dart';
import '../group_selection/group_avatar.dart';
import '../events/timeline_widgets.dart';
import 'member_count_badge.dart';

class InstanceTimelineItem extends StatelessWidget {
  final GroupInstanceWithGroup instanceWithGroup;
  final LimitedUserGroups group;
  final bool isFirst;
  final bool isLast;
  final bool isNewest;

  const InstanceTimelineItem({
    super.key,
    required this.instanceWithGroup,
    required this.group,
    required this.isFirst,
    required this.isLast,
    required this.isNewest,
  });

  @override
  Widget build(BuildContext context) {
    final instance = instanceWithGroup.instance;
    final world = instance.world;
    final detectedTime = instanceWithGroup.firstDetectedAt;
    final timeLabel = _formatTime(detectedTime);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TimelineRail(
              label: timeLabel,
              height: UiConstants.groupAvatarLg,
              isFirst: isFirst,
              isLast: isLast,
            ),
            SizedBox(width: context.m3e.spacing.sm),
            GroupAvatar(
              group: group,
              size: UiConstants.groupAvatarLg,
              borderRadius: context.m3e.shapes.square.sm,
            ),
            SizedBox(width: context.m3e.spacing.sm),
            Expanded(
              child: SizedBox(
                height: UiConstants.groupAvatarLg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name ?? 'Unknown Group',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    SizedBox(height: context.m3e.spacing.xs),
                    Text(
                      world.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: context.m3e.spacing.sm),
            MemberCountBadge(userCount: instance.nUsers),
            if (isNewest) ...[
              SizedBox(width: context.m3e.spacing.sm),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.m3e.spacing.sm,
                  vertical: context.m3e.spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: context.m3e.shapes.round.xs,
                ),
                child: Text(
                  'New',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (!isLast) TimelineConnector(height: context.m3e.spacing.sm),
      ],
    );
  }

  String _formatTime(DateTime? date) {
    final dt = date ?? DateTime.now();
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final isAm = hour < 12;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = isAm ? 'AM' : 'PM';
    return '$hour12:$minute $suffix';
  }
}
