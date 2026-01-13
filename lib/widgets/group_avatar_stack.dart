import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:portal/utils/vrchat_image_utils.dart';

class GroupAvatarStack extends ConsumerWidget {
  final List<LimitedUserGroups> groups;
  final VoidCallback? onTap;
  final double spacing;
  final int maxStackedCount;

  const GroupAvatarStack({
    super.key,
    required this.groups,
    this.onTap,
    this.spacing = 24.0,
    this.maxStackedCount = 5,
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
      ref: ref,
      width: 48,
      height: 48,
      shape: BoxShape.circle,
      fallbackWidget: hasImage
          ? null
          : Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getAvatarColor(group.id ?? ''),
              ),
              child: Center(
                child: Text(
                  _getInitials(group.name ?? 'Group'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
      ),
      child: Center(
        child: Text(
          '+$count',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length > 1 ? 2 : 1).toUpperCase();
  }

  Color _getAvatarColor(String id) {
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFF43F5E),
      const Color(0xFFF97316),
      const Color(0xFFEAB308),
      const Color(0xFF22C55E),
      const Color(0xFF10B981),
      const Color(0xFF06B6D4),
      const Color(0xFF3B82F6),
    ];

    final hash = id.hashCode;
    return colors[hash.abs() % colors.length];
  }
}
