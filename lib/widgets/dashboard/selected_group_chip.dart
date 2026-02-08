import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/app_constants.dart';
import '../../constants/ui_constants.dart';
import '../../utils/group_utils.dart';
import '../cached_image.dart';

class SelectedGroupChip extends StatelessWidget {
  final LimitedUserGroups group;
  final bool isBoosted;
  final bool isMonitoring;
  final VoidCallback onToggleBoost;

  const SelectedGroupChip({
    super.key,
    required this.group,
    required this.isBoosted,
    required this.isMonitoring,
    required this.onToggleBoost,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasImage = group.iconUrl != null && group.iconUrl!.isNotEmpty;
    final avatarSize = UiConstants.groupAvatarMd;
    final avatarRadius = context.m3e.shapes.square.sm;
    final boostLabel = !isMonitoring
        ? 'Start monitoring to enable boost'
        : isBoosted
        ? 'Boost active'
        : 'Boost polling for ${AppConstants.boostDurationMinutes} min';
    final surfaceColor = isBoosted
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final foregroundColor = isBoosted
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final textColor = isBoosted ? scheme.onPrimaryContainer : scheme.onSurface;
    final borderRadius = context.m3e.shapes.round.md;

    return Tooltip(
      message: boostLabel,
      child: Material(
        color: surfaceColor,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onToggleBoost,
          borderRadius: borderRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.m3e.spacing.sm,
              vertical: context.m3e.spacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    borderRadius: avatarRadius,
                    color: hasImage ? null : GroupUtils.getAvatarColor(group),
                  ),
                  child: ClipRRect(
                    borderRadius: avatarRadius,
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
                                  fontSize: 10,
                                ),
                              ),
                            ),
                      showLoadingIndicator: false,
                    ),
                  ),
                ),
                SizedBox(width: context.m3e.spacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    group.name ?? 'Group',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: textColor),
                  ),
                ),
                if (isBoosted) ...[
                  SizedBox(width: context.m3e.spacing.xs),
                  Icon(Icons.flash_on, size: 18, color: foregroundColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
