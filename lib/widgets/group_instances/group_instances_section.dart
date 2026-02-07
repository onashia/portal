import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../../constants/ui_constants.dart';
import '../../models/group_instance_with_group.dart';
import '../../utils/vrchat_image_utils.dart';
import 'group_instance_card.dart';

class GroupInstancesSection extends StatelessWidget {
  final LimitedUserGroups group;
  final List<GroupInstanceWithGroup> instances;
  final List<GroupInstanceWithGroup> newInstances;
  final VoidCallback onRefresh;

  const GroupInstancesSection({
    super.key,
    required this.group,
    required this.instances,
    required this.newInstances,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupHeader(context, group),
        SizedBox(height: context.m3e.spacing.sm),
        ...instances.map((instanceWithGroup) {
          final isNew = newInstances.contains(instanceWithGroup);
          return GroupInstanceCard(
            instanceWithGroup: instanceWithGroup,
            group: group,
            isNew: isNew,
          );
        }),
      ],
    );
  }

  Widget _buildGroupHeader(BuildContext context, LimitedUserGroups group) {
    if (group.id == null || group.id!.isEmpty) {
      return const SizedBox.shrink();
    }

    final avatarRadius = context.m3e.shapes.square.sm;

    return Row(
      children: [
        if (group.iconUrl != null && group.iconUrl!.isNotEmpty)
          ClipRRect(
            borderRadius: avatarRadius,
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: UiConstants.groupAvatarMd,
              height: UiConstants.groupAvatarMd,
              child: CachedImage(
                imageUrl: group.iconUrl!,
                width: UiConstants.groupAvatarMd,
                height: UiConstants.groupAvatarMd,
                fit: BoxFit.cover,
                showLoadingIndicator: false,
              ),
            ),
          ),
        SizedBox(width: context.m3e.spacing.sm),
        Expanded(
          child: Text(
            group.name ?? 'Unknown Group',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: context.m3e.shapes.round.md,
          ),
          child: Text(
            '${instances.length} instance${instances.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ],
    );
  }
}
