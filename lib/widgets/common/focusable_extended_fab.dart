import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

// Local Portal fork of fab_m3e's ExtendedFabM3E.
// The intentional divergence is exposing focusNode/autofocus on the actual
// interactive control for accessibility focus management.
// Keep all other behavior aligned with upstream unless Portal has a specific
// accessibility reason to differ.
// When upgrading fab_m3e, compare this file with the installed upstream
// implementation and delete this fork if equivalent focus support lands there.
class FocusableExtendedFab extends StatelessWidget {
  const FocusableExtendedFab({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.tooltip,
    this.heroTag,
    this.kind = FabM3EKind.primary,
    this.size = FabM3ESize.regular,
    this.shapeFamily = FabM3EShapeFamily.round,
    this.density = FabM3EDensity.regular,
    this.elevation,
    this.expand = false,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
  });

  final Widget label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Object? heroTag;
  final FabM3EKind kind;
  final FabM3ESize size;
  final FabM3EShapeFamily shapeFamily;
  final FabM3EDensity density;
  final double? elevation;
  final bool expand;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tokens = FabTokensAdapter(context);
    final metrics = tokens.metrics(density);
    final backgroundColor = tokens.bg(kind);
    final foregroundColor = tokens.fg(kind);
    final shape = tokens.shape(shapeFamily, size);

    final child = DefaultTextStyle.merge(
      style: tokens.labelStyle().copyWith(color: foregroundColor),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            IconTheme.merge(
              data: IconThemeData(
                color: foregroundColor,
                size: metrics.iconSize,
              ),
              child: icon!,
            ),
            const SizedBox(width: 12),
          ],
          Flexible(child: label),
        ],
      ),
    );

    final button = ConstrainedBox(
      constraints: BoxConstraints(minHeight: metrics.extendedHeight),
      child: Material(
        shape: shape,
        color: backgroundColor,
        elevation: elevation ?? metrics.elevationRest,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          // Keep a hover callback so InkWell renders desktop hover states.
          onHover: (_) {},
          focusNode: focusNode,
          autofocus: autofocus,
          canRequestFocus: onPressed != null,
          child: Padding(
            padding: metrics.extendedPadding,
            child: Align(alignment: Alignment.center, child: child),
          ),
        ),
      ),
    );

    final expandedButton = expand
        ? SizedBox(width: double.infinity, child: button)
        : button;
    final core = tooltip != null && tooltip!.isNotEmpty
        ? Tooltip(message: tooltip!, preferBelow: false, child: expandedButton)
        : expandedButton;

    Widget wrapped = core;
    if (heroTag != null &&
        context.findAncestorWidgetOfExactType<Hero>() == null) {
      wrapped = Hero(tag: heroTag!, child: core);
    }

    if (semanticLabel == null) {
      return wrapped;
    }
    return Semantics(button: true, label: semanticLabel, child: wrapped);
  }
}
