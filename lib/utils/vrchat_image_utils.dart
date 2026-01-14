import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/auth_provider.dart';
import 'lru_cache.dart';

class FileIdInfo {
  final String fileId;
  final int version;

  FileIdInfo({required this.fileId, this.version = 1});
}

FileIdInfo extractFileIdFromUrl(String url) {
  if (url.isEmpty) {
    throw ArgumentError('URL cannot be empty');
  }

  final uri = Uri.parse(url);

  final pathSegments = uri.pathSegments;

  // VRChat URLs contain file IDs in path segments like: /.../file_abc123/2
  // We search for segments starting with 'file_' and optionally parse version
  for (int i = 0; i < pathSegments.length; i++) {
    final segment = pathSegments[i];

    if (segment.startsWith('file_')) {
      final fileId = segment;

      int version = 1;

      // Version is optional and appears as next segment if present
      if (i + 1 < pathSegments.length) {
        final nextSegment = pathSegments[i + 1];
        final parsedVersion = int.tryParse(nextSegment);
        if (parsedVersion != null) {
          version = parsedVersion;
        }
      }

      return FileIdInfo(fileId: fileId, version: version);
    }
  }

  throw FormatException('Could not extract file ID from URL: $url');
}

Future<Uint8List?> fetchImageBytesWithAuth(
  WidgetRef ref,
  String imageUrl,
) async {
  if (imageUrl.isEmpty) {
    return null;
  }

  try {
    final api = ref.read(vrchatApiProvider);
    final fileIdInfo = extractFileIdFromUrl(imageUrl);

    debugPrint('[IMAGE_FETCH] Fetching image from API: $imageUrl');

    ref.read(apiCallCounterProvider.notifier).incrementApiCall();

    final response = await api.rawApi.getFilesApi().downloadFileVersion(
      fileId: fileIdInfo.fileId,
      versionId: fileIdInfo.version,
    );
    debugPrint('[IMAGE_FETCH] Successfully fetched image: $imageUrl');
    return response.data as Uint8List;
  } catch (e) {
    debugPrint('[IMAGE_FETCH] Failed to fetch image: $e');
    return null;
  }
}

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  final LRUCache<String, Uint8List> _memoryCache = LRUCache<String, Uint8List>(
    maxSize: 100,
  );
  io.Directory? _cacheDirectory;
  bool _isInitialized = false;

  Future<void> _initialize() async {
    if (_isInitialized) return;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _cacheDirectory = io.Directory('${appDocDir.path}/image_cache');
      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('[IMAGE_CACHE] Failed to initialize cache directory: $e');
    }
  }

  String _getCacheKey(String url) {
    final fileIdInfo = extractFileIdFromUrl(url);
    return '${fileIdInfo.fileId}_${fileIdInfo.version}';
  }

  Future<Uint8List?> getCachedImage(String url) async {
    if (url.isEmpty) return null;

    final cacheKey = _getCacheKey(url);

    debugPrint('[IMAGE_CACHE] Checking cache for: $url (key: $cacheKey)');

    final cachedBytes = _memoryCache.get(cacheKey);
    if (cachedBytes != null) {
      debugPrint('[IMAGE_CACHE] Memory cache HIT for: $url');
      return cachedBytes;
    }

    debugPrint(
      '[IMAGE_CACHE] Memory cache MISS for: $url, checking disk cache',
    );

    await _initialize();

    if (_cacheDirectory != null) {
      try {
        final file = io.File('${_cacheDirectory!.path}/$cacheKey');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _memoryCache.put(cacheKey, bytes);
          debugPrint('[IMAGE_CACHE] Disk cache HIT for: $url');
          return bytes;
        }
      } catch (e) {
        debugPrint('[IMAGE_CACHE] Failed to read from disk cache: $e');
      }
    }

    debugPrint(
      '[IMAGE_CACHE] Complete cache MISS for: $url, will fetch from API',
    );
    return null;
  }

  Future<void> cacheImage(String url, Uint8List bytes) async {
    if (url.isEmpty) return;

    final cacheKey = _getCacheKey(url);

    // Store in both caches for maximum availability
    _memoryCache.put(cacheKey, bytes);

    await _initialize();

    // Persist to disk for app restarts
    if (_cacheDirectory != null) {
      try {
        final file = io.File('${_cacheDirectory!.path}/$cacheKey');
        await file.writeAsBytes(bytes);
      } catch (e) {
        debugPrint('[IMAGE_CACHE] Failed to write to disk cache: $e');
      }
    }
  }

  Future<void> clearCache() async {
    _memoryCache.clear();

    if (_cacheDirectory != null) {
      try {
        if (await _cacheDirectory!.exists()) {
          await _cacheDirectory!.delete(recursive: true);
          await _cacheDirectory!.create(recursive: true);
        }
      } catch (e) {
        debugPrint('[IMAGE_CACHE] Failed to clear disk cache: $e');
      }
    }
  }
}

class CachedImage extends ConsumerWidget {
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
    required this.ref,
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

  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (imageUrl.isEmpty) {
      return _buildFallback(context);
    }

    final cacheService = ImageCacheService();

    return FutureBuilder<Uint8List?>(
      future: _loadImage(cacheService),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (showLoadingIndicator) {
            return _buildLoading(context);
          }
          return _buildFallback(context);
        }

        final bytes = snapshot.data;
        if (bytes != null) {
          return _buildImage(bytes, context, true);
        }

        return _buildFallback(context);
      },
    );
  }

  Future<Uint8List?> _loadImage(ImageCacheService cacheService) async {
    debugPrint('[CACHED_IMAGE] _loadImage called for: $imageUrl');

    final cachedBytes = await cacheService.getCachedImage(imageUrl);
    if (cachedBytes != null) {
      debugPrint('[CACHED_IMAGE] Returning cached image for: $imageUrl');
      return cachedBytes;
    }

    debugPrint('[CACHED_IMAGE] Cache miss, fetching from API for: $imageUrl');
    final fetchedBytes = await fetchImageBytesWithAuth(ref, imageUrl);
    if (fetchedBytes != null) {
      debugPrint(
        '[CACHED_IMAGE] Successfully fetched, caching image for: $imageUrl',
      );
      await cacheService.cacheImage(imageUrl, fetchedBytes);
    } else {
      debugPrint('[CACHED_IMAGE] Failed to fetch image: $imageUrl');
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
      width: width,
      height: height,
      fit: fit,
    );

    Widget shapedWidget;

    if (shape == BoxShape.circle) {
      shapedWidget = ClipOval(
        child: SizedBox(width: width, height: height, child: imageWidget),
      );
    } else {
      shapedWidget = imageWidget;
    }

    final container = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: shape,
        color: applyBackgroundColor
            ? (backgroundColor ??
                  Theme.of(context).colorScheme.surfaceContainerHighest)
            : null,
        border: border,
        boxShadow: boxShadow,
      ),
      child: shapedWidget,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: container);
    }

    return container;
  }

  Widget _buildLoading(BuildContext context) {
    final container = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: shape,
        color:
            fallbackBackgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        border: border,
        boxShadow: boxShadow,
      ),
      child: Center(
        child: SizedBox(
          width: (width ?? 48) * 0.3,
          height: (height ?? 48) * 0.3,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );

    return onTap != null
        ? GestureDetector(onTap: onTap, child: container)
        : container;
  }

  Widget _buildFallback(BuildContext context) {
    if (fallbackWidget != null) {
      final container = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          shape: shape,
          color:
              fallbackBackgroundColor ??
              Theme.of(context).colorScheme.surfaceContainerHighest,
          border: border,
          boxShadow: boxShadow,
        ),
        child: fallbackWidget,
      );

      return onTap != null
          ? GestureDetector(onTap: onTap, child: container)
          : container;
    }

    final container = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: shape,
        color:
            fallbackBackgroundColor ??
            Theme.of(context).colorScheme.surfaceContainerHighest,
        border: border,
        boxShadow: boxShadow,
      ),
      child: fallbackIcon != null
          ? Icon(
              fallbackIcon,
              size: (width ?? 48) * 0.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : null,
    );

    return onTap != null
        ? GestureDetector(onTap: onTap, child: container)
        : container;
  }
}
