import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/app_constants.dart';
import '../../constants/icon_sizes.dart';
import '../../constants/ui_constants.dart';
import '../group_selection/group_avatar.dart';

class SelectedGroupChip extends StatelessWidget {
  final LimitedUserGroups group;
  final bool isBoosted;
  final bool hasError;
  final String? errorMessage;
  final bool isMonitoring;
  final VoidCallback onToggleBoost;

  const SelectedGroupChip({
    super.key,
    required this.group,
    required this.isBoosted,
    this.hasError = false,
    this.errorMessage,
    required this.isMonitoring,
    required this.onToggleBoost,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groupName = group.name ?? 'Group';
    const boostActiveLabel = 'Boost is active';
    final boostLabel = isBoosted
        ? boostActiveLabel
        : 'Boost polling for ${AppConstants.boostDurationMinutes} min';
    final resolvedErrorMessage = errorMessage ?? 'Failed to fetch instances';
    final tooltipMessage = hasError
        ? isBoosted
              ? '$resolvedErrorMessage. $boostActiveLabel'
              : resolvedErrorMessage
        : boostLabel;
    final surfaceColor = hasError
        ? scheme.errorContainer
        : isBoosted
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    final foregroundColor = hasError
        ? scheme.onErrorContainer
        : isBoosted
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final textColor = hasError
        ? scheme.onErrorContainer
        : isBoosted
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    final borderRadius = context.m3e.shapes.round.md;
    final semanticLabel = '$groupName. $tooltipMessage';

    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onToggleBoost,
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltipMessage,
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
                    GroupAvatar(
                      group: group,
                      size: UiConstants.groupAvatarMd,
                      borderRadius: context.m3e.shapes.square.sm,
                    ),
                    SizedBox(width: context.m3e.spacing.xs),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(color: textColor),
                      ),
                    ),
                    if (hasError) ...[
                      SizedBox(width: context.m3e.spacing.xs),
                      Icon(
                        Icons.error_outline,
                        size: IconSizes.xxs,
                        color: foregroundColor,
                      ),
                    ],
                    if (isBoosted) ...[
                      SizedBox(width: context.m3e.spacing.xs),
                      Icon(
                        Icons.flash_on,
                        size: IconSizes.xxs,
                        color: foregroundColor,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
