import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/group_monitor_provider.dart';
import 'package:portal/utils/vrchat_image_utils.dart';
import '../models/group_instance_with_group.dart';

class GroupInstanceList extends ConsumerWidget {
  final String userId;
  final VoidCallback onRefresh;

  const GroupInstanceList({
    super.key,
    required this.userId,
    required this.onRefresh,
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

    return Column(
      children: [
        for (var i = 0; i < groupsWithInstances.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _GroupInstancesSection(
              group: groupsWithInstances[i].value.isEmpty
                  ? LimitedUserGroups()
                  : monitorState.allGroups.firstWhere(
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
            const SizedBox(height: 16),
      ],
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
              const SizedBox(height: 16),
              Text(
                'No Groups Selected',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
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
            const SizedBox(height: 16),
            Text(
              state.isMonitoring ? 'No Instances Open' : 'Monitoring Paused',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
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
        const SizedBox(height: 8),
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

    return Row(
      children: [
        if (group.iconUrl != null && group.iconUrl!.isNotEmpty)
          ClipOval(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CachedImage(
                imageUrl: group.iconUrl!,
                ref: ref,
                width: 24,
                height: 24,
                fit: BoxFit.cover,
                showLoadingIndicator: false,
              ),
            ),
          ),
        const SizedBox(width: 8),
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
            borderRadius: BorderRadius.circular(12),
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

    return Card(
      elevation: isNew ? 4 : 1,
      child: Container(
        decoration: isNew
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildWorldThumbnail(context, ref, world),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (group.id != null && group.id!.isNotEmpty)
                        _buildGroupInfo(context, ref, group),
                      _buildWorldInfo(context, world),
                      const SizedBox(height: 4),
                      _buildInstanceInfo(context, instance),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
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
        borderRadius: BorderRadius.circular(12),
        child: CachedImage(
          imageUrl: thumbnailUrl,
          ref: ref,
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

    return Row(
      children: [
        ClipOval(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CachedImage(
              imageUrl: group.iconUrl!,
              ref: ref,
              width: 16,
              height: 16,
              fit: BoxFit.cover,
              showLoadingIndicator: false,
            ),
          ),
        ),
        const SizedBox(width: 6),
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
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(4),
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
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
        const SizedBox(width: 4),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
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
