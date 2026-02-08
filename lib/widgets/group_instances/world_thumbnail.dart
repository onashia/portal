import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';
import '../../constants/ui_constants.dart';
import '../cached_image.dart';

class WorldThumbnail extends StatelessWidget {
  final String? imageUrl;
  final double size;

  const WorldThumbnail({
    super.key,
    this.imageUrl,
    this.size = UiConstants.worldThumbnailMd,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: context.m3e.shapes.round.md,
        child: CachedImage(
          imageUrl: imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fallbackWidget: _buildFallback(context),
          showLoadingIndicator: true,
        ),
      );
    }

    return _buildFallback(context);
  }

  Widget _buildFallback(BuildContext context) {
    return Icon(
      Icons.public,
      size: size / 2,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }
}
