import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portal/services/image_cache_service.dart';
import 'package:portal/utils/app_logger.dart';
import 'package:portal/utils/vrchat_image_utils.dart';

class CachedImage extends ConsumerStatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxShape shape;
  final BoxFit fit;
  final IconData? fallbackIcon;
  final Widget? fallbackWidget;
  final Color? fallbackBackgroundColor;
  final Color? backgroundColor;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final bool showLoadingIndicator;
  final VoidCallback? onTap;

  const CachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.shape = BoxShape.rectangle,
    this.fit = BoxFit.cover,
    this.fallbackIcon,
    this.fallbackWidget,
    this.fallbackBackgroundColor,
    this.backgroundColor,
    this.border,
    this.boxShadow,
    this.showLoadingIndicator = true,
    this.onTap,
  });

  @override
  ConsumerState<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends ConsumerState<CachedImage> {
  Uint8List? _cachedBytes;
  Future<Uint8List?>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _resetLoad();
  }

  @override
  void didUpdateWidget(CachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _cachedBytes = null;
      _resetLoad();
    }
  }

  @override
  void dispose() {
    _cachedBytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrl.isEmpty) {
      return _buildFallback(context);
    }
    final loadFuture = _loadFuture;
    if (loadFuture == null) {
      return _buildFallback(context);
    }

    return FutureBuilder<Uint8List?>(
      key: ValueKey('cached_image_${widget.imageUrl}'),
      future: loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          _cachedBytes = snapshot.data;
        }

        final bytes = _cachedBytes ?? snapshot.data;
        if (bytes != null) {
          return _buildImage(bytes, context, true);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          if (widget.showLoadingIndicator) {
            return _buildLoading(context);
          }
          return _buildFallback(context);
        }

        return _buildFallback(context);
      },
    );
  }

  void _resetLoad() {
    if (widget.imageUrl.isEmpty) {
      _loadFuture = null;
      return;
    }

    final cacheService = ImageCacheService();
    _loadFuture = _loadImage(cacheService, ref);
  }

  Future<Uint8List?> _loadImage(
    ImageCacheService cacheService,
    WidgetRef ref,
  ) async {
    AppLogger.debug(
      '_loadImage called for: ${widget.imageUrl}',
      subCategory: 'cached_image',
    );

    final cachedBytes = await cacheService.getCachedImage(widget.imageUrl);
    if (cachedBytes != null) {
      AppLogger.debug(
        'Returning cached image for: ${widget.imageUrl}',
        subCategory: 'cached_image',
      );
      return cachedBytes;
    }

    AppLogger.debug(
      'Cache miss, fetching from API for: ${widget.imageUrl}',
      subCategory: 'cached_image',
    );
    final fetchedBytes = await fetchImageBytesWithAuth(ref, widget.imageUrl);
    if (fetchedBytes != null) {
      AppLogger.debug(
        'Successfully fetched, caching image for: ${widget.imageUrl}',
        subCategory: 'cached_image',
      );
      await cacheService.cacheImage(widget.imageUrl, fetchedBytes);
    } else {
      AppLogger.debug(
        'Failed to fetch image: ${widget.imageUrl}',
        subCategory: 'cached_image',
      );
    }

    return fetchedBytes;
  }

  Widget _buildImage(
    Uint8List bytes,
    BuildContext context,
    bool applyBackgroundColor,
  ) {
    final imageWidget = Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
    );

    Widget shapedWidget;

    if (widget.shape == BoxShape.circle) {
      shapedWidget = ClipOval(
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: imageWidget,
        ),
      );
    } else {
      shapedWidget = imageWidget;
    }

    final container = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        shape: widget.shape,
        color: applyBackgroundColor
            ? (widget.backgroundColor ??
                  Theme.of(context).colorScheme.surfaceContainerHighest)
            : null,
        border: widget.border,
        boxShadow: widget.boxShadow,
      ),
      child: shapedWidget,
    );

    if (widget.onTap != null) {
      return GestureDetector(onTap: widget.onTap, child: container);
    }

    return container;
  }

  Widget _buildLoading(BuildContext context) {
    final container = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        shape: widget.shape,
        color:
            widget.fallbackBackgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        border: widget.border,
        boxShadow: widget.boxShadow,
      ),
      child: Center(
        child: SizedBox(
          width: (widget.width ?? 48) * 0.3,
          height: (widget.height ?? 48) * 0.3,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );

    return widget.onTap != null
        ? GestureDetector(onTap: widget.onTap, child: container)
        : container;
  }

  Widget _buildFallback(BuildContext context) {
    if (widget.fallbackWidget != null) {
      final container = Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          shape: widget.shape,
          color:
              widget.fallbackBackgroundColor ??
              Theme.of(context).colorScheme.surfaceContainerHighest,
          border: widget.border,
          boxShadow: widget.boxShadow,
        ),
        child: widget.fallbackWidget,
      );

      return widget.onTap != null
          ? GestureDetector(onTap: widget.onTap, child: container)
          : container;
    }

    final container = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        shape: widget.shape,
        color:
            widget.fallbackBackgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        border: widget.border,
        boxShadow: widget.boxShadow,
      ),
      child: widget.fallbackIcon != null
          ? Icon(
              widget.fallbackIcon,
              size: (widget.width ?? 48) * 0.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : null,
    );

    return widget.onTap != null
        ? GestureDetector(onTap: widget.onTap, child: container)
        : container;
  }
}
