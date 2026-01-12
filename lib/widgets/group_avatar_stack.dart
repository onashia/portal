import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/utils/vrchat_image_utils.dart';

class GroupAvatarStack extends ConsumerWidget {
  final List<LimitedUserGroups> groups;
  final int newInstancesCount;
  final VoidCallback? onTap;

  const GroupAvatarStack({
    super.key,
    required this.groups,
    this.newInstancesCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) {
      return _buildEmptyState(context);
    }

    final displayCount = groups.length > 5 ? 5 : groups.length;
    final overflowCount = groups.length > 5 ? groups.length - 5 : 0;

    final totalWidth = displayCount * 12.0 + 48;

    return SizedBox(
      width: totalWidth,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ...List.generate(displayCount, (index) {
            final group = groups[index];
            final offset = index * 12.0;
            return Positioned(
              left: offset,
              child: _buildGroupAvatar(context, ref, group, index),
            );
          }),
          if (overflowCount > 0)
            Positioned(
              left: displayCount * 12.0,
              child: _buildOverflowAvatar(context, overflowCount),
            ),
          if (newInstancesCount > 0) _buildNotificationBadge(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
        ),
        child: Icon(
          Icons.add,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
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
        child: hasImage
            ? ClipOval(
                child: FutureBuilder<Uint8List?>(
                  future: fetchImageBytesWithAuth(ref, group.iconUrl!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    }

                    final bytes = snapshot.data;
                    if (bytes != null) {
                      return SizedBox(
                        width: 48,
                        height: 48,
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                        ),
                      );
                    }

                    return _buildFallbackAvatar(context, group);
                  },
                ),
              )
            : _buildFallbackAvatar(context, group),
      ),
    );
  }

  Widget _buildFallbackAvatar(
    BuildContext context,
    LimitedUserGroups group,
  ) {
    final initials = _getInitials(group.name ?? 'Group');
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getAvatarColor(group.id ?? ''),
      ),
      child: Center(
        child: Text(
          initials,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
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

  Widget _buildNotificationBadge(BuildContext context) {
    return Positioned(
      top: -4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.surface,
            width: 2,
          ),
        ),
        constraints: const BoxConstraints(
          minWidth: 20,
          minHeight: 20,
        ),
        child: Center(
          child: Text(
            newInstancesCount > 9 ? '9+' : newInstancesCount.toString(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
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
