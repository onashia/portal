import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../../constants/app_constants.dart';
import '../../constants/ui_constants.dart';
import '../../providers/group_monitor_provider.dart';
import '../../utils/group_utils.dart';
import '../../utils/vrchat_image_utils.dart';
import '../group_instance_list.dart';

class DashboardGroupMonitoringSection extends ConsumerWidget {
  final String userId;
  final GroupMonitorState monitorState;
  final List<LimitedUserGroups> selectedGroups;

  const DashboardGroupMonitoringSection({
    super.key,
    required this.userId,
    required this.monitorState,
    required this.selectedGroups,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cardTheme = Theme.of(context).cardTheme;
    final baseShape =
        cardTheme.shape as RoundedRectangleBorder? ??
        RoundedRectangleBorder(borderRadius: context.m3e.shapes.round.md);
    final outlineColor = scheme.outlineVariant.withValues(alpha: 0.4);

    return Card(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: baseShape.copyWith(side: BorderSide(color: outlineColor)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group Monitoring',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: context.m3e.spacing.md),
            Expanded(
              child: GroupInstanceList(
                userId: userId,
                scrollable: true,
                onRefresh: () {
                  ref
                      .read(groupMonitorProvider(userId).notifier)
                      .fetchGroupInstances();
                },
              ),
            ),
            SizedBox(height: context.m3e.spacing.md),
            Divider(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            SizedBox(height: context.m3e.spacing.sm),
            Row(
              children: [
                Text(
                  'Selected Groups',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: context.m3e.spacing.sm),
                Text(
                  '\u2022',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: context.m3e.spacing.sm),
                Text(
                  selectedGroups.length.toString(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (selectedGroups.isNotEmpty) ...[
              SizedBox(height: context.m3e.spacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final group in selectedGroups) ...[
                      _SelectedGroupChip(
                        group: group,
                        isBoosted:
                            monitorState.boostedGroupId == group.groupId &&
                            monitorState.isBoostActive,
                        isMonitoring: monitorState.isMonitoring,
                        onToggleBoost: () {
                          final notifier = ref.read(
                            groupMonitorProvider(userId).notifier,
                          );
                          if (!monitorState.isMonitoring) {
                            return;
                          }
                          if (group.groupId != null) {
                            notifier.toggleBoostForGroup(group.groupId!);
                          }
                        },
                      ),
                      SizedBox(width: context.m3e.spacing.sm),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectedGroupChip extends StatelessWidget {
  final LimitedUserGroups group;
  final bool isBoosted;
  final bool isMonitoring;
  final VoidCallback onToggleBoost;

  const _SelectedGroupChip({
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
