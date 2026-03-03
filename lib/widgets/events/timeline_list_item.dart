import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/ui_constants.dart';
import '../group_selection/group_avatar.dart';
import 'timeline_widgets.dart';

class TimelineListItem extends StatelessWidget {
  final String timeLabel;
  final LimitedUserGroups? group;
  final String subtitle;
  final Widget? trailing;
  final bool isFirst;
  final bool isLast;
  final String? groupName;

  const TimelineListItem({
    super.key,
    required this.timeLabel,
    required this.group,
    required this.subtitle,
    this.trailing,
    required this.isFirst,
    required this.isLast,
    this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatarSize = UiConstants.groupAvatarLg;
    final effectiveGroup = group ?? LimitedUserGroups();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          spacing: context.m3e.spacing.sm,
          children: [
            TimelineRail(
              label: timeLabel,
              height: avatarSize,
              isFirst: isFirst,
              isLast: isLast,
            ),
            GroupAvatar(
              group: effectiveGroup,
              size: avatarSize,
              borderRadius: context.m3e.shapes.square.sm,
            ),
            Expanded(child: _buildContent(context, scheme)),
            ...trailing != null ? [trailing!] : [],
          ],
        ),
        if (!isLast) TimelineConnector(height: context.m3e.spacing.sm),
      ],
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          groupName ?? group?.name ?? 'Unknown Group',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        SizedBox(height: context.m3e.spacing.xs),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}
