import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../constants/icon_sizes.dart';
import '../../constants/ui_constants.dart';
import '../../providers/vrchat_status_provider.dart';
import 'vrchat_status_visuals.dart';

class VrchatStatusCompactView extends StatelessWidget {
  const VrchatStatusCompactView({
    super.key,
    required this.state,
    required this.onTap,
  });

  final VrchatStatusState? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m3e = context.m3e;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: m3e.spacing.md,
          vertical: m3e.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: m3e.shapes.round.sm,
        ),
        child: _buildCompactContent(context, scheme, textTheme, m3e),
      ),
    );
  }

  Widget _buildCompactContent(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
    M3ETheme m3e,
  ) {
    if (state == null || state!.isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: m3e.spacing.md,
        children: [
          SizedBox(
            width: UiConstants.vrchatCompactLoaderSize,
            height: UiConstants.vrchatCompactLoaderSize,
            child: const CircularProgressIndicator(
              strokeWidth: UiConstants.vrchatCompactLoaderStrokeWidth,
            ),
          ),
          Text('Loading...', style: textTheme.bodySmall),
        ],
      );
    }

    if (state!.errorMessage != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: m3e.spacing.md,
        children: [
          Icon(Icons.error_outline, size: IconSizes.xxs, color: scheme.error),
          Text(
            'Error',
            style: textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
      );
    }

    final status = state!.status!;
    final statusColor = statusColorForIndicator(status.indicator, scheme);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: UiConstants.vrchatStatusDotSize,
          height: UiConstants.vrchatStatusDotSize,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        SizedBox(width: m3e.spacing.md),
        Flexible(
          child: Text(
            status.description,
            style: textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (status.activeIncidents.isNotEmpty) ...[
          SizedBox(width: m3e.spacing.sm),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: m3e.spacing.xs,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: m3e.shapes.round.md,
            ),
            child: Text(
              '${status.activeIncidents.length}',
              style: textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
