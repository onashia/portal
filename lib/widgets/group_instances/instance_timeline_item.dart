import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../models/group_instance_with_group.dart';
import '../../utils/date_time_utils.dart';
import '../events/timeline_list_item.dart';
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
    final timeLabel = detectedTime != null
        ? DateTimeUtils.formatLocalJm(detectedTime)
        : '—';

    return TimelineListItem(
      timeLabel: timeLabel,
      group: group,
      groupName: group.name ?? 'Unknown Group',
      subtitle: world.name,
      isFirst: isFirst,
      isLast: isLast,
      trailing: Row(
        spacing: context.m3e.spacing.sm,
        mainAxisSize: MainAxisSize.min,
        children: [
          MemberCountBadge(userCount: instance.nUsers),
          if (isNewest)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.m3e.spacing.md,
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
      ),
    );
  }
}
