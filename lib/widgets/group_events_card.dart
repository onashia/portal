import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/ui_constants.dart';
import '../models/group_calendar_event.dart';
import '../providers/group_calendar_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../utils/group_utils.dart';
import '../utils/vrchat_image_utils.dart';

class GroupEventsCard extends ConsumerWidget {
  final String userId;

  const GroupEventsCard({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendarState = ref.watch(groupCalendarProvider(userId));
    final monitorState = ref.watch(groupMonitorProvider(userId));
    final scheme = Theme.of(context).colorScheme;
    final cardTheme = Theme.of(context).cardTheme;
    final baseShape =
        cardTheme.shape as RoundedRectangleBorder? ??
        RoundedRectangleBorder(borderRadius: context.m3e.shapes.round.md);
    final outlineColor = scheme.outlineVariant.withValues(alpha: 0.4);
    final todayLabel = _formatDateLabel(DateTime.now());

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
            _buildHeader(context, ref, calendarState, todayLabel),
            SizedBox(height: context.m3e.spacing.md),
            Expanded(
              child: _buildContent(context, calendarState, monitorState),
            ),
            if (calendarState.groupErrors.isNotEmpty) ...[
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                'Some groups failed to load (${calendarState.groupErrors.length})',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    GroupCalendarState calendarState,
    String todayLabel,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Today's Events",
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: context.m3e.spacing.xs),
              Text(
                todayLabel,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    GroupCalendarState calendarState,
    GroupMonitorState monitorState,
  ) {
    if (monitorState.selectedGroupIds.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.event_busy,
        title: 'No Groups Selected',
        message: 'Select groups in Group Monitoring to see events.',
      );
    }

    if (calendarState.isLoading && calendarState.todayEvents.isEmpty) {
      return _buildLoadingState(context);
    }

    if (calendarState.todayEvents.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.event_available,
        title: 'No Events Today',
        message: 'Your groups have nothing scheduled for today.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final event = calendarState.todayEvents[index];
        return _EventListItem(event: event);
      },
      separatorBuilder: (context, index) =>
          SizedBox(height: context.m3e.spacing.sm),
      itemCount: calendarState.todayEvents.length,
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const LoadingIndicatorM3E(
            variant: LoadingIndicatorM3EVariant.defaultStyle,
            semanticLabel: 'Loading events',
          ),
          SizedBox(height: context.m3e.spacing.sm),
          Text(
            'Loading events...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            SizedBox(height: context.m3e.spacing.sm),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: context.m3e.spacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateLabel(DateTime date) {
    final local = date.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[local.month - 1];
    return '$month ${local.day}, ${local.year}';
  }
}

class _EventListItem extends StatelessWidget {
  final GroupCalendarEvent event;

  const _EventListItem({required this.event});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = event.group;
    final badgeLabel = _buildBadgeLabel(event.event);
    final avatarSize = UiConstants.groupAvatarLg;
    final avatarRadius = context.m3e.shapes.square.sm;
    final eventImageUrl = event.event.imageUrl;
    final groupImageUrl = group?.iconUrl;
    final imageUrl = (eventImageUrl?.isNotEmpty ?? false)
        ? eventImageUrl
        : groupImageUrl;
    final hasImage = imageUrl?.isNotEmpty ?? false;
    final groupName = group?.name ?? _fallbackGroupName(event.groupId);

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: context.m3e.shapes.round.md,
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: BoxDecoration(
                borderRadius: avatarRadius,
                color: hasImage
                    ? null
                    : GroupUtils.getAvatarColor(group ?? LimitedUserGroups()),
              ),
              child: ClipRRect(
                borderRadius: avatarRadius,
                clipBehavior: Clip.antiAlias,
                child: CachedImage(
                  imageUrl: imageUrl ?? '',
                  width: avatarSize,
                  height: avatarSize,
                  fit: BoxFit.cover,
                  showLoadingIndicator: false,
                  fallbackWidget: hasImage
                      ? null
                      : Center(
                          child: Text(
                            GroupUtils.getInitials(
                              group ?? LimitedUserGroups(),
                            ),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                ),
              ),
            ),
            SizedBox(width: context.m3e.spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  SizedBox(height: context.m3e.spacing.xs),
                  Text(
                    event.event.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  SizedBox(height: context.m3e.spacing.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      SizedBox(width: context.m3e.spacing.xs),
                      Expanded(
                        child: Text(
                          _formatTimeRange(event.event),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: context.m3e.spacing.sm),
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: _EventBadge(label: badgeLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildBadgeLabel(CalendarEvent event) {
    final interested = event.interestedUserCount;
    if (interested != null && interested > 0) {
      return '$interested interested';
    }

    final rawCategory = event.category.value.replaceAll('_', ' ');
    if (rawCategory.isEmpty) {
      return 'Other';
    }
    return rawCategory[0].toUpperCase() + rawCategory.substring(1);
  }

  String _formatTimeRange(CalendarEvent event) {
    final start = event.startsAt.toLocal();
    final end = event.endsAt.toLocal();
    return '${_formatTime(start)} - ${_formatTime(end)}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final isAm = hour < 12;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = isAm ? 'AM' : 'PM';
    return '$hour12:$minute $suffix';
  }

  String _fallbackGroupName(String groupId) {
    if (groupId.length <= 8) {
      return groupId;
    }
    return groupId.substring(0, 8);
  }
}

class _EventBadge extends StatelessWidget {
  final String label;

  const _EventBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.m3e.spacing.sm,
        vertical: context.m3e.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: context.m3e.shapes.round.xs,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
