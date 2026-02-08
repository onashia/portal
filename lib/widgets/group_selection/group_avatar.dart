import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/ui_constants.dart';
import '../../utils/group_utils.dart';
import '../../utils/vrchat_image_utils.dart';

class GroupAvatar extends StatelessWidget {
  final LimitedUserGroups group;
  final double? size;

  const GroupAvatar({super.key, required this.group, this.size});

  @override
  Widget build(BuildContext context) {
    final avatarSize = size ?? UiConstants.groupAvatarLg;
    final hasImage = group.iconUrl != null && group.iconUrl!.isNotEmpty;

    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        borderRadius: context.m3e.shapes.square.md,
        color: hasImage ? null : GroupUtils.getAvatarColor(group),
      ),
      child: ClipRRect(
        borderRadius: context.m3e.shapes.square.md,
        clipBehavior: Clip.antiAlias,
        child: CachedImage(
          imageUrl: hasImage ? group.iconUrl! : '',
          width: avatarSize,
          height: avatarSize,
          fallbackWidget: hasImage
              ? null
              : Center(
                  child: Text(
                    GroupUtils.getInitials(group),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
          showLoadingIndicator: false,
        ),
      ),
    );
  }
}
