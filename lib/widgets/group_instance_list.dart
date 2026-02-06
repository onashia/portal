import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../constants/ui_constants.dart';
import '../providers/group_monitor_provider.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:portal/utils/vrchat_image_utils.dart';
import '../models/group_instance_with_group.dart';

class GroupInstanceList extends ConsumerWidget {
  final String userId;
  final VoidCallback onRefresh;
  final bool scrollable;

  const GroupInstanceList({
    super.key,
    required this.userId,
    required this.onRefresh,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(groupMonitorProvider(userId));

    final groupsWithInstances = monitorState.groupInstances.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList();

    if (groupsWithInstances.isEmpty) {
      return _buildEmptyState(context, monitorState);
    }

    if (!scrollable) {
      return Column(
        children: [
          for (var i = 0; i < groupsWithInstances.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _GroupInstancesSection(
                group: monitorState.allGroups.firstWhere(
                  (g) => g.groupId == groupsWithInstances[i].key,
                  orElse: () => LimitedUserGroups(),
                ),
                groupId: groupsWithInstances[i].key,
                instances: groupsWithInstances[i].value,
                newInstances: monitorState.newInstances,
                onRefresh: onRefresh,
              ),
            ),
          if (groupsWithInstances.length > 1)
            for (var i = 0; i < groupsWithInstances.length - 1; i++)
              SizedBox(height: context.m3e.spacing.md),
        ],
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final entry = groupsWithInstances[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: _GroupInstancesSection(
            group: monitorState.allGroups.firstWhere(
              (g) => g.groupId == entry.key,
              orElse: () => LimitedUserGroups(),
            ),
            groupId: entry.key,
            instances: entry.value,
            newInstances: monitorState.newInstances,
            onRefresh: onRefresh,
          ),
        );
      },
      separatorBuilder: (context, index) =>
          SizedBox(height: context.m3e.spacing.md),
      itemCount: groupsWithInstances.length,
    );
  }

  Widget _buildEmptyState(BuildContext context, GroupMonitorState state) {
    if (state.selectedGroupIds.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.group_off,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              SizedBox(height: context.m3e.spacing.md),
              Text(
                'No Groups Selected',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                'Select groups to monitor for new instances',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final hasErrors = state.groupErrors.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasErrors ? Icons.error_outline : Icons.wifi_off,
              size: 64,
              color: hasErrors
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: context.m3e.spacing.md),
            Text(
              state.isMonitoring ? 'No Instances Open' : 'Monitoring Paused',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: context.m3e.spacing.sm),
            Text(
              state.isMonitoring
                  ? 'No instances are currently open for your selected groups'
                  : 'Start monitoring to see open instances',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupInstancesSection extends ConsumerWidget {
  final LimitedUserGroups group;
  final String groupId;
  final List<GroupInstanceWithGroup> instances;
  final List<GroupInstanceWithGroup> newInstances;
  final VoidCallback onRefresh;

  const _GroupInstancesSection({
    required this.group,
    required this.groupId,
    required this.instances,
    required this.newInstances,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupHeader(context, ref, group),
        SizedBox(height: context.m3e.spacing.sm),
        ...instances.map((instanceWithGroup) {
          final isNew = newInstances.contains(instanceWithGroup);
          return _InstanceCard(
            instanceWithGroup: instanceWithGroup,
            group: group,
            isNew: isNew,
          );
        }),
      ],
    );
  }

  Widget _buildGroupHeader(
    BuildContext context,
    WidgetRef ref,
    LimitedUserGroups group,
  ) {
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

class _InstanceCard extends ConsumerWidget {
  final GroupInstanceWithGroup instanceWithGroup;
  final LimitedUserGroups group;
  final bool isNew;

  const _InstanceCard({
    required this.instanceWithGroup,
    required this.group,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                _buildWorldThumbnail(context, ref, world),
                SizedBox(width: context.m3e.spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (group.id != null && group.id!.isNotEmpty)
                        _buildGroupInfo(context, ref, group),
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

  Widget _buildWorldThumbnail(
    BuildContext context,
    WidgetRef ref,
    World? world,
  ) {
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

  Widget _buildGroupInfo(
    BuildContext context,
    WidgetRef ref,
    LimitedUserGroups group,
  ) {
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
