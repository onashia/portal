import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../../constants/ui_constants.dart';
import '../../theme/user_status_extension.dart';
import '../cached_image.dart';

class UserProfileImage extends StatelessWidget {
  final CurrentUser currentUser;
  final StreamedCurrentUser? streamedUser;
  final double size;
  final bool showStatusBorder;

  const UserProfileImage({
    super.key,
    required this.currentUser,
    this.streamedUser,
    this.size = UiConstants.userAvatarMd,
    this.showStatusBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final status = _resolveStatus();
    final borderColor = showStatusBorder
        ? status.getColor(context)
        : Colors.transparent;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2),
      ),
      child: CachedImage(
        imageUrl: _getImageUrl(),
        width: size,
        height: size,
        shape: BoxShape.circle,
        fallbackIcon: Icons.person,
      ),
    );
  }

  UserStatus _resolveStatus() {
    return streamedUser?.status ?? currentUser.status;
  }

  String _getImageUrl() {
    if (streamedUser != null && streamedUser!.profilePicOverride.isNotEmpty) {
      return streamedUser!.profilePicOverride;
    }
    if (currentUser.profilePicOverrideThumbnail.isNotEmpty) {
      return currentUser.profilePicOverrideThumbnail;
    }
    if (streamedUser != null &&
        streamedUser!.currentAvatarThumbnailImageUrl.isNotEmpty) {
      return streamedUser!.currentAvatarThumbnailImageUrl;
    }
    return currentUser.currentAvatarThumbnailImageUrl;
  }
}
