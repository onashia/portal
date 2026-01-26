import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/utils/group_utils.dart';
import 'package:portal/utils/vrchat_image_utils.dart';
import 'package:portal/constants/app_typography.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class GroupAvatarStack extends ConsumerWidget {
  final List<LimitedUserGroups> groups;
  final VoidCallback? onTap;

  const GroupAvatarStack({super.key, required this.groups, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const avatarSize = 48.0;
        const spacing = 8.0;
        const overflowSize = 48.0;
        final availableWidth = constraints.maxWidth;

        int maxAvatarsThatFit;
        if (groups.length == 1) {
          maxAvatarsThatFit = availableWidth >= avatarSize ? 1 : 0;
        } else {
          final remainingWidth = availableWidth - avatarSize - overflowSize;
          maxAvatarsThatFit = remainingWidth > 0
              ? 1 + (remainingWidth / (avatarSize + spacing)).floor()
              : 1;
          maxAvatarsThatFit = maxAvatarsThatFit.clamp(1, groups.length);
        }

        final displayGroups = groups.take(maxAvatarsThatFit).toList();
        final overflowCount = groups.length - maxAvatarsThatFit;

        return Row(
          spacing: 8.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            ...displayGroups.map(
              (group) => _buildGroupAvatar(context, ref, group),
            ),
            if (overflowCount > 0) _buildOverflowAvatar(context, overflowCount),
          ],
        );
      },
    );
  }

  Widget _buildGroupAvatar(
    BuildContext context,
    WidgetRef ref,
    LimitedUserGroups group,
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
              decoration: const BoxDecoration(shape: BoxShape.circle),
              color: GroupUtils.getAvatarColor(group),
              child: Center(
                child: Text(
                  GroupUtils.getInitials(group),
                  style: AppTypography.bodySmall.copyWith(color: Colors.white),
                ),
              ),
            ),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.12),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
      onTap: onTap,
    );
  }

  Widget _buildOverflowAvatar(BuildContext context, int count) {
    return Container(
      decoration: const BoxDecoration(shape: BoxShape.circle),
      color: Theme.of(context).colorScheme.primaryContainer,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: Center(
        child: Text(
          count > 9 ? '9+' : count.toString(),
          style: AppTypography.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
