import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

class LoadingState extends StatelessWidget {
  final String? message;
  final String semanticLabel;
  final EdgeInsetsGeometry? padding;
  final double? scale;

  const LoadingState({
    super.key,
    this.message,
    this.semanticLabel = 'Loading',
    this.padding,
    this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const LoadingIndicatorM3E(
          variant: LoadingIndicatorM3EVariant.defaultStyle,
        ),
        if (message != null) ...[
          SizedBox(height: context.m3e.spacing.md),
          Text(
            message!,
            style: context.m3e.typography.base.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    final scaledContent = scale != null
        ? Transform.scale(scale: scale!, child: content)
        : content;

    final paddedContent = padding != null
        ? Padding(padding: padding!, child: scaledContent)
        : scaledContent;

    return Center(child: paddedContent);
  }
}
