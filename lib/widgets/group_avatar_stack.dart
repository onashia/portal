import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/utils/group_utils.dart';
import 'package:portal/utils/vrchat_image_utils.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class GroupAvatarStack extends ConsumerWidget {
  final List<LimitedUserGroups> groups;
  final VoidCallback? onTap;
  final double spacing;
  final int maxStackedCount;

  const GroupAvatarStack({
    super.key,
    required this.groups,
    this.onTap,
    this.spacing = AppConstants.defaultSpacing,
    this.maxStackedCount = AppConstants.maxStackedAvatars,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayCount = groups.length > maxStackedCount
        ? maxStackedCount
        : groups.length;
    final overflowCount = groups.length > maxStackedCount
        ? groups.length - maxStackedCount
        : 0;

    final totalWidth = displayCount * spacing + 48;

    return SizedBox(
      width: totalWidth,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ...List.generate(displayCount, (index) {
            final group = groups[index];
            final offset = index * spacing;
            return Positioned(
              left: offset,
              child: _buildGroupAvatar(context, ref, group, index),
            );
          }),
          if (overflowCount > 0)
            Positioned(
              left: displayCount * spacing,
              child: _buildOverflowAvatar(context, overflowCount),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupAvatar(
    BuildContext context,
    WidgetRef ref,
    LimitedUserGroups group,
    int index,
  ) {
    final hasImage = group.iconUrl != null && group.iconUrl!.isNotEmpty;

    return CachedImage(
      imageUrl: hasImage ? group.iconUrl! : '',
      width: 48,
      height: 48,
      shape: BoxShape.circle,
      fallbackWidget: hasImage
          ? null
          : Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: GroupUtils.getAvatarColor(group),
              ),
              child: Center(
                child: Text(
                  GroupUtils.getInitials(group),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
      border: Border.all(
        color: Theme.of(context).colorScheme.surface,
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
      onTap: onTap,
    );
  }

  Widget _buildOverflowAvatar(BuildContext context, int count) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary,
      ),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Center(
        child: Text(
          count > 9 ? '9+' : count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
