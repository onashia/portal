import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/ui_constants.dart';
import '../../utils/group_utils.dart';
import '../cached_image.dart';

class GroupAvatar extends StatelessWidget {
  final LimitedUserGroups group;
  final double? size;
  final BorderRadius? borderRadius;
  final TextStyle? fallbackTextStyle;
  final bool showFallback;

  const GroupAvatar({
    super.key,
    required this.group,
    this.size,
    this.borderRadius,
    this.fallbackTextStyle,
    this.showFallback = true,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = size ?? UiConstants.groupAvatarLg;
    final hasImage = group.iconUrl != null && group.iconUrl!.isNotEmpty;
    final defaultBorderRadius = context.m3e.shapes.square.md;

    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? defaultBorderRadius,
        color: hasImage ? null : GroupUtils.getAvatarColor(group),
      ),
      child: ClipRRect(
        borderRadius: borderRadius ?? defaultBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: CachedImage(
          imageUrl: hasImage ? group.iconUrl! : '',
          width: avatarSize,
          height: avatarSize,
          fallbackWidget: showFallback && !hasImage
              ? Center(
                  child: Text(
                    GroupUtils.getInitials(group),
                    style:
                        fallbackTextStyle ??
                        context.m3e.typography.base.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                )
              : null,
          showLoadingIndicator: false,
        ),
      ),
    );
  }
}
