import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import '../../constants/ui_constants.dart';
import '../cached_image.dart';

class GroupInfoRow extends StatelessWidget {
  final String? iconUrl;
  final String? name;
  final bool showNewBadge;

  const GroupInfoRow({
    super.key,
    this.iconUrl,
    this.name,
    this.showNewBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    if (iconUrl == null || iconUrl!.isEmpty) {
      return Flexible(
        child: Text(
          name ?? 'Unknown Group',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );
    }

    final avatarRadius = context.m3e.shapes.square.sm;

    return Row(
      children: [
        ClipRRect(
          borderRadius: avatarRadius,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: UiConstants.groupAvatarSm,
            height: UiConstants.groupAvatarSm,
            child: CachedImage(
              imageUrl: iconUrl!,
              width: UiConstants.groupAvatarSm,
              height: UiConstants.groupAvatarSm,
              fit: BoxFit.cover,
              showLoadingIndicator: false,
            ),
          ),
        ),
        SizedBox(width: context.m3e.spacing.sm),
        Flexible(
          child: Text(
            name ?? 'Unknown Group',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (showNewBadge) ...[
          SizedBox(width: context.m3e.spacing.sm),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.m3e.spacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: context.m3e.shapes.round.xs,
            ),
            child: Text(
              'NEW',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
