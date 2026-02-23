import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class DashboardSideSheetLayout extends StatelessWidget {
  static const Key shellKey = ValueKey('dashboard_side_sheet_shell');

  final Widget content;
  final Widget sideSheet;
  final double sheetWidth;
  final double progress;
  final VoidCallback onClose;

  const DashboardSideSheetLayout({
    super.key,
    required this.content,
    required this.sideSheet,
    required this.sheetWidth,
    required this.progress,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = context.m3e.spacing.sm;
    final leftShadowGutter = context.m3e.spacing.md;
    final rightInset = context.m3e.spacing.lg;
    final bottomInset = context.m3e.spacing.lg;
    final shellWidth = sheetWidth + rightInset + leftShadowGutter;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final opacityProgress = Curves.easeOut.transform(
      (clampedProgress * 2).clamp(0.0, 1.0),
    );
    const minVisibleOpacity = 0.02;
    final isVisible = opacityProgress > minVisibleOpacity;
    final sheetTranslateX = shellWidth * (1 - clampedProgress);

    return SizedBox.expand(
      child: Stack(
        children: [
          content,
          if (isVisible)
            Positioned.fill(
              child: GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          Positioned(
            right: 0,
            top: topInset,
            bottom: 0,
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(sheetTranslateX, 0),
                child: SizedBox(
                  key: shellKey,
                  width: shellWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1.0,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: leftShadowGutter,
                        right: rightInset,
                        bottom: bottomInset,
                      ),
                      child: IgnorePointer(
                        ignoring: !isVisible,
                        child: Opacity(
                          opacity: opacityProgress,
                          child: sideSheet,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
