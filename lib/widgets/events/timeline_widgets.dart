import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../constants/ui_constants.dart';

class TimelineRail extends StatelessWidget {
  final String label;
  final double height;
  final bool isFirst;
  final bool isLast;

  const TimelineRail({
    super.key,
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

class TimelineConnector extends StatelessWidget {
  final double height;

  const TimelineConnector({super.key, required this.height});

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
