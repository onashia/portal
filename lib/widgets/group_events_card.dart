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

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: calendarState.todayEvents.length,
      itemBuilder: (context, index) {
        final event = calendarState.todayEvents[index];
        final isLast = index == calendarState.todayEvents.length - 1;
        return _EventListItem(
          event: event,
          isFirst: index == 0,
          isLast: isLast,
        );
      },
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
  final bool isFirst;
  final bool isLast;

  const _EventListItem({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = event.group;
    final badgeLabel = _buildBadgeLabel(event.event);
    final avatarSize = UiConstants.groupAvatarLg;
    final rowHeight = avatarSize;
    final avatarRadius = context.m3e.shapes.square.sm;
    final eventImageUrl = event.event.imageUrl;
    final groupImageUrl = group?.iconUrl;
    final imageUrl = (eventImageUrl?.isNotEmpty ?? false)
        ? eventImageUrl
        : groupImageUrl;
    final hasImage = imageUrl?.isNotEmpty ?? false;
    final groupName = group?.name ?? _fallbackGroupName(event.groupId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _TimelineRail(
              label: _formatTime(event.event.startsAt),
              height: rowHeight,
              isFirst: isFirst,
              isLast: isLast,
            ),
            SizedBox(width: context.m3e.spacing.sm),
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
        if (!isLast) _TimelineConnector(height: context.m3e.spacing.sm),
      ],
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

class _TimelineRail extends StatelessWidget {
  final String label;
  final double height;
  final bool isFirst;
  final bool isLast;

  const _TimelineRail({
    required this.label,
    required this.height,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final railPadding = context.m3e.spacing.sm;
    final labelPadding =
        railPadding + UiConstants.timelineDotSize + context.m3e.spacing.xs;

    return SizedBox(
      width: UiConstants.timelineRailWidth,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.centerRight,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _TimelinePainter(
                dotColor: scheme.primary,
                lineColor: scheme.outlineVariant.withValues(alpha: 0.6),
                dotSize: UiConstants.timelineDotSize,
                lineWidth: UiConstants.timelineLineWidth,
                railPadding: railPadding,
                isFirst: isFirst,
                isLast: isLast,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(right: labelPadding),
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  final double height;

  const _TimelineConnector({required this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final railPadding = context.m3e.spacing.sm;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: UiConstants.timelineRailWidth,
            height: height,
            child: CustomPaint(
              painter: _TimelineConnectorPainter(
                lineColor: scheme.outlineVariant.withValues(alpha: 0.6),
                dotSize: UiConstants.timelineDotSize,
                lineWidth: UiConstants.timelineLineWidth,
                railPadding: railPadding,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

class _TimelineConnectorPainter extends CustomPainter {
  final Color lineColor;
  final double dotSize;
  final double lineWidth;
  final double railPadding;

  const _TimelineConnectorPainter({
    required this.lineColor,
    required this.dotSize,
    required this.lineWidth,
    required this.railPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width - railPadding - (dotSize / 2);
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
  }

  @override
  bool shouldRepaint(covariant _TimelineConnectorPainter oldDelegate) {
    return lineColor != oldDelegate.lineColor ||
        dotSize != oldDelegate.dotSize ||
        lineWidth != oldDelegate.lineWidth ||
        railPadding != oldDelegate.railPadding;
  }
}

class _TimelinePainter extends CustomPainter {
  final Color dotColor;
  final Color lineColor;
  final double dotSize;
  final double lineWidth;
  final double railPadding;
  final bool isFirst;
  final bool isLast;

  const _TimelinePainter({
    required this.dotColor,
    required this.lineColor,
    required this.dotSize,
    required this.lineWidth,
    required this.railPadding,
    required this.isFirst,
    required this.isLast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final dotRadius = dotSize / 2;
    final x = size.width - railPadding - dotRadius;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;

    if (!isFirst) {
      canvas.drawLine(Offset(x, 0), Offset(x, centerY - dotRadius), linePaint);
    }
    if (!isLast) {
      canvas.drawLine(
        Offset(x, centerY + dotRadius),
        Offset(x, size.height),
        linePaint,
      );
    }

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(x, centerY), dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return dotColor != oldDelegate.dotColor ||
        lineColor != oldDelegate.lineColor ||
        dotSize != oldDelegate.dotSize ||
        lineWidth != oldDelegate.lineWidth ||
        railPadding != oldDelegate.railPadding ||
        isFirst != oldDelegate.isFirst ||
        isLast != oldDelegate.isLast;
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
