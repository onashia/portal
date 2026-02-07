import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../theme/status_colors.dart';
import '../../utils/vrchat_image_utils.dart';

class DashboardUserCard extends StatelessWidget {
  final CurrentUser currentUser;
  final StreamedCurrentUser? streamedUser;

  const DashboardUserCard({
    super.key,
    required this.currentUser,
    this.streamedUser,
  });

  @override
  Widget build(BuildContext context) {
    final status = _resolveUserStatus(currentUser, streamedUser);
    return Padding(
      padding: EdgeInsets.all(context.m3e.spacing.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _getStatusColor(context, status),
                width: 2,
              ),
            ),
            child: CachedImage(
              imageUrl: _getUserProfileImageUrl(
                currentUser,
                streamedUser: streamedUser,
              ),
              width: 56,
              height: 56,
              shape: BoxShape.circle,
              fallbackIcon: Icons.person,
            ),
          ),
          SizedBox(width: context.m3e.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  streamedUser?.displayName ?? currentUser.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: context.m3e.spacing.xs),
                Row(
                  children: [
                    Icon(
                      _getStatusIcon(status),
                      size: 16,
                      color: _getStatusColor(context, status),
                    ),
                    SizedBox(width: context.m3e.spacing.sm),
                    Text(
                      _getStatusText(status),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _getStatusColor(context, status),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  UserStatus _resolveUserStatus(
    CurrentUser currentUser,
    StreamedCurrentUser? streamedUser,
  ) {
    return streamedUser?.status ?? currentUser.status;
  }

  String _getUserProfileImageUrl(
    CurrentUser currentUser, {
    StreamedCurrentUser? streamedUser,
  }) {
    if (streamedUser != null && streamedUser.profilePicOverride.isNotEmpty) {
      return streamedUser.profilePicOverride;
    }
    if (currentUser.profilePicOverrideThumbnail.isNotEmpty) {
      return currentUser.profilePicOverrideThumbnail;
    }
    if (streamedUser != null &&
        streamedUser.currentAvatarThumbnailImageUrl.isNotEmpty) {
      return streamedUser.currentAvatarThumbnailImageUrl;
    }
    return currentUser.currentAvatarThumbnailImageUrl;
  }

  IconData _getStatusIcon(UserStatus status) {
    switch (status) {
      case UserStatus.askMe:
      case UserStatus.busy:
      case UserStatus.joinMe:
        return Icons.circle;
      case UserStatus.offline:
        return Icons.offline_bolt;
      case UserStatus.active:
        return Icons.play_circle;
    }
  }

  Color _getStatusColor(BuildContext context, UserStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final statusColors = Theme.of(context).extension<StatusColors>();

    switch (status) {
      case UserStatus.active:
        return statusColors?.active ?? scheme.primary;
      case UserStatus.askMe:
        return statusColors?.askMe ?? scheme.tertiary;
      case UserStatus.busy:
        return statusColors?.busy ?? scheme.error;
      case UserStatus.joinMe:
        return statusColors?.joinMe ?? scheme.secondary;
      case UserStatus.offline:
        return statusColors?.offline ?? scheme.outline;
    }
  }

  String _getStatusText(UserStatus status) {
    switch (status) {
      case UserStatus.active:
        return 'Active';
      case UserStatus.askMe:
        return 'Ask Me';
      case UserStatus.busy:
        return 'Busy';
      case UserStatus.joinMe:
        return 'Join Me';
      case UserStatus.offline:
        return 'Offline';
    }
  }
}
