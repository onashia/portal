import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../../constants/ui_constants.dart';
import '../../models/group_instance_with_group.dart';
import '../cached_image.dart';

class GroupInstanceCard extends StatelessWidget {
  final GroupInstanceWithGroup instanceWithGroup;
  final LimitedUserGroups group;
  final bool isNew;

  const GroupInstanceCard({
    super.key,
    required this.instanceWithGroup,
    required this.group,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context) {
    final instance = instanceWithGroup.instance;
    final world = instance.world;
    final cardTheme = Theme.of(context).cardTheme;
    final baseShape =
        cardTheme.shape as RoundedRectangleBorder? ??
        RoundedRectangleBorder(borderRadius: context.m3e.shapes.round.md);
    final borderRadiusGeometry = baseShape.borderRadius;
    final borderRadius = borderRadiusGeometry.resolve(
      Directionality.of(context),
    );

    return Card(
      child: Container(
        decoration: isNew
            ? BoxDecoration(
                borderRadius: borderRadiusGeometry,
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildWorldThumbnail(context, world),
                SizedBox(width: context.m3e.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (group.id != null && group.id!.isNotEmpty)
                        _buildGroupInfo(context, group),
                      _buildWorldInfo(context, world),
                      SizedBox(height: context.m3e.spacing.xs),
                      _buildInstanceInfo(context, instance),
                    ],
                  ),
                ),
                SizedBox(width: context.m3e.spacing.md),
                _buildMemberCount(context, instance),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorldThumbnail(BuildContext context, World? world) {
    final thumbnailUrl = world?.thumbnailImageUrl;

    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: context.m3e.shapes.round.md,
        child: CachedImage(
          imageUrl: thumbnailUrl,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          fallbackWidget: _buildThumbnailFallback(context),
          showLoadingIndicator: true,
        ),
      );
    }

    return _buildThumbnailFallback(context);
  }

  Widget _buildThumbnailFallback(BuildContext context) {
    return Icon(
      Icons.public,
      size: 32,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  Widget _buildGroupInfo(BuildContext context, LimitedUserGroups group) {
    if (group.iconUrl == null || group.iconUrl!.isEmpty) {
      return Flexible(
        child: Text(
          group.name ?? 'Unknown Group',
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
              imageUrl: group.iconUrl!,
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
            group.name ?? 'Unknown Group',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (isNew) ...[
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

  Widget _buildWorldInfo(BuildContext context, World? world) {
    final worldName = world?.name ?? 'Unknown World';
    return Text(
      worldName,
      style: context.m3e.typography.base.titleMedium,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _buildInstanceInfo(BuildContext context, Instance instance) {
    return Row(
      children: [
        Icon(
          Icons.location_on,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: context.m3e.spacing.xs),
        Expanded(
          child: Text(
            instance.location,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildMemberCount(BuildContext context, Instance instance) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: context.m3e.shapes.round.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          SizedBox(width: context.m3e.spacing.xs),
          Text(
            instance.nUsers.toString(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
