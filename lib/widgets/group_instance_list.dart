import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:portal/providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import 'package:portal/utils/vrchat_image_utils.dart';

Future<Image> fetchImageWithAuth(
  WidgetRef ref,
  String imageUrl, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) async {
  try {
    final api = ref.read(vrchatApiProvider);
    final fileIdInfo = extractFileIdFromUrl(imageUrl);
    final response = await api.rawApi.getFilesApi().downloadFileVersion(
      fileId: fileIdInfo.fileId,
      versionId: fileIdInfo.version,
    );
    final bytes = response.data as Uint8List;
    return Image.memory(
      bytes,
      width: width,
      height: height,
      fit: fit,
    );
  } catch (e) {
    debugPrint('[IMAGE_FETCH] Failed to fetch image: $e');
    rethrow;
  }
}

class GroupInstanceList extends ConsumerWidget {
  final VoidCallback onRefresh;
  final String userId;

  const GroupInstanceList({
    super.key,
    required this.onRefresh,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(groupMonitorProvider(userId));

    final allInstances = monitorState.groupInstances.values.expand((e) => e).toList();

    if (allInstances.isEmpty) {
      return _buildEmptyState(context, monitorState);
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: allInstances.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final instance = allInstances[index];
          final isNew = monitorState.newInstances.contains(instance);

          return _InstanceCard(
            instance: instance,
            allGroups: monitorState.allGroups,
            isNew: isNew,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    GroupMonitorState state,
  ) {
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _InstanceCard extends ConsumerWidget {
  final GroupInstance instance;
  final List<LimitedUserGroups> allGroups;
  final bool isNew;

  const _InstanceCard({
    required this.instance,
    required this.allGroups,
    required this.isNew,
  });

  LimitedUserGroups? getGroup() {
    final locationParts = instance.location.split(':');
    if (locationParts.isEmpty) return null;

    final worldId = locationParts[0];
    return allGroups.firstWhere(
      (g) => g.id == worldId,
      orElse: () => allGroups.firstWhere(
        (g) => instance.location.contains(g.id ?? ''),
        orElse: () => LimitedUserGroups(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = getGroup();
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
                      if (group != null && group.id != null)
                        _buildGroupInfo(context, ref, group!),
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
      return FutureBuilder<Image>(
        future: fetchImageWithAuth(
          ref,
          thumbnailUrl,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return _buildThumbnailFallback(context);
          }

          final image = snapshot.data;
          if (image != null) {
            return SizedBox(
              width: 64,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: image,
              ),
            );
          }

          return _buildThumbnailFallback(context);
        },
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
        FutureBuilder<Image>(
          future: fetchImageWithAuth(
            ref,
            group.iconUrl!,
            width: 16,
            height: 16,
            fit: BoxFit.cover,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data != null) {
              return ClipOval(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: snapshot.data!,
                ),
              );
            }
            return const SizedBox.shrink();
          },
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
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }

  Widget _buildInstanceInfo(
    BuildContext context,
    GroupInstance instance,
  ) {
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

  Widget _buildMemberCount(
    BuildContext context,
    GroupInstance instance,
  ) {
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
            instance.memberCount.toString(),
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
