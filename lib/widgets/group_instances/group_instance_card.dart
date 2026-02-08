import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../../models/group_instance_with_group.dart';
import 'member_count_badge.dart';
import 'instance_location_row.dart';
import 'world_thumbnail.dart';
import 'group_info_row.dart';

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
                WorldThumbnail(imageUrl: world.thumbnailImageUrl),
                SizedBox(width: context.m3e.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (group.id != null && group.id!.isNotEmpty)
                        GroupInfoRow(
                          iconUrl: group.iconUrl,
                          name: group.name,
                          showNewBadge: isNew,
                        ),
                      Text(
                        world.name,
                        style: context.m3e.typography.base.titleMedium,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      SizedBox(height: context.m3e.spacing.xs),
                      InstanceLocationRow(location: instance.location),
                    ],
                  ),
                ),
                SizedBox(width: context.m3e.spacing.md),
                MemberCountBadge(userCount: instance.nUsers),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
