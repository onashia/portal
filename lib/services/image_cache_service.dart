import 'dart:convert';
import 'dart:io' as io;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:portal/utils/app_logger.dart';
import 'package:portal/utils/lru_cache.dart';
import 'package:portal/utils/vrchat_image_utils.dart';

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
      AppLogger.error(
        'Failed to initialize cache directory: $e',
        subCategory: 'image_cache',
        error: e,
      );
    }
  }

  @visibleForTesting
  String getCacheKeyForTesting(String url) {
    final fileIdInfo = extractFileIdFromUrl(url);
    final bytes = utf8.encode('${fileIdInfo.fileId}_${fileIdInfo.version}');
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  Future<Uint8List?> getCachedImage(String url) async {
    if (url.isEmpty) return null;

    final String cacheKey;
    try {
      cacheKey = getCacheKeyForTesting(url);
    } catch (e) {
      AppLogger.error(
        'Could not get cache key for URL: $url',
        subCategory: 'image_cache',
        error: e,
      );
      return null;
    }

    AppLogger.debug(
      'Checking cache for: $url (key: $cacheKey)',
      subCategory: 'image_cache',
    );

    final cachedBytes = _memoryCache.get(cacheKey);
    if (cachedBytes != null) {
      AppLogger.debug('Memory cache HIT for: $url', subCategory: 'image_cache');
      return cachedBytes;
    }

    AppLogger.debug(
      'Memory cache MISS for: $url, checking disk cache',
      subCategory: 'image_cache',
    );

    await _initialize();

    if (_cacheDirectory != null) {
      try {
        final file = io.File('${_cacheDirectory!.path}/$cacheKey');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _memoryCache.put(cacheKey, bytes);
          AppLogger.debug(
            'Disk cache HIT for: $url',
            subCategory: 'image_cache',
          );
          return bytes;
        }
      } catch (e) {
        AppLogger.error(
          'Failed to read from disk cache for $url: $e',
          subCategory: 'image_cache',
          error: e,
        );
      }
    }

    AppLogger.debug(
      'Complete cache MISS for: $url, will fetch from API',
      subCategory: 'image_cache',
    );
    return null;
  }

  Future<void> cacheImage(String url, Uint8List bytes) async {
    if (url.isEmpty) return;

    final String cacheKey;
    try {
      cacheKey = getCacheKeyForTesting(url);
    } catch (e) {
      AppLogger.error(
        'Could not get cache key for URL: $url',
        subCategory: 'image_cache',
        error: e,
      );
      return;
    }

    _memoryCache.put(cacheKey, bytes);

    await _initialize();

    if (_cacheDirectory != null) {
      try {
        final file = io.File('${_cacheDirectory!.path}/$cacheKey');
        await file.writeAsBytes(bytes);
      } catch (e) {
        AppLogger.error(
          'Failed to write to disk cache for $url: $e',
          subCategory: 'image_cache',
          error: e,
        );
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
        AppLogger.error(
          'Failed to clear disk cache: $e',
          subCategory: 'image_cache',
          error: e,
        );
      }
    }
  }

  @visibleForTesting
  static void reset() {
    _instance._memoryCache.clear();
    _instance._cacheDirectory = null;
    _instance._isInitialized = false;
  }
}
