import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/utils/app_logger.dart';
import 'package:portal/utils/lru_cache.dart';
import 'package:portal/utils/vrchat_image_utils.dart';

class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  final ByteBudgetLRUCache<String, Uint8List> _memoryCache =
      ByteBudgetLRUCache<String, Uint8List>(
        maxEntries: AppConstants.maxAvatarCacheSize,
        maxBytes: AppConstants.maxAvatarMemoryCacheBytes,
        sizeOf: (bytes) => bytes.lengthInBytes,
      );
  final Map<String, Future<Uint8List?>> _inFlightRequests =
      <String, Future<Uint8List?>>{};
  final Map<String, DateTime> _negativeCacheUntilByKey = <String, DateTime>{};

  io.Directory? _cacheDirectory;
  bool _isInitialized = false;
  DateTime? _lastPrunedAt;
  DateTime Function() _nowProvider = DateTime.now;

  Future<void> _initialize() async {
    if (_isInitialized) {
      return;
    }

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

  String? _safeCacheKey(String url) {
    try {
      return getCacheKeyForTesting(url);
    } catch (e) {
      AppLogger.error(
        'Could not get cache key for URL: $url',
        subCategory: 'image_cache',
        error: e,
      );
      return null;
    }
  }

  @visibleForTesting
  String getCacheKeyForTesting(String url) {
    final fileIdInfo = extractFileIdFromUrl(url);
    final bytes = utf8.encode('${fileIdInfo.fileId}_${fileIdInfo.version}');
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  Future<Uint8List?> _getCachedImageByKey({
    required String url,
    required String cacheKey,
  }) async {
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
    await _pruneDiskCacheIfNeeded();

    if (_cacheDirectory != null) {
      try {
        final file = io.File('${_cacheDirectory!.path}/$cacheKey');
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (_canStoreInMemory(bytes)) {
            _memoryCache.put(cacheKey, bytes);
          }
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

  Future<Uint8List?> getCachedImage(String url) async {
    if (url.isEmpty) {
      return null;
    }

    final cacheKey = _safeCacheKey(url);
    if (cacheKey == null) {
      return null;
    }

    return _getCachedImageByKey(url: url, cacheKey: cacheKey);
  }

  Future<void> _cacheImageByKey({
    required String url,
    required String cacheKey,
    required Uint8List bytes,
  }) async {
    if (_canStoreInMemory(bytes)) {
      _memoryCache.put(cacheKey, bytes);
    }
    _negativeCacheUntilByKey.remove(cacheKey);

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

    await _pruneDiskCacheIfNeeded();
  }

  Future<void> cacheImage(String url, Uint8List bytes) async {
    if (url.isEmpty) {
      return;
    }

    final cacheKey = _safeCacheKey(url);
    if (cacheKey == null) {
      return;
    }

    await _cacheImageByKey(url: url, cacheKey: cacheKey, bytes: bytes);
  }

  Future<Uint8List?> getOrFetchImage(
    String url,
    Future<Uint8List?> Function() fetcher,
  ) async {
    if (url.isEmpty) {
      return null;
    }

    final cacheKey = _safeCacheKey(url);
    if (cacheKey == null) {
      return null;
    }

    final now = _nowProvider();
    final negativeCachedUntil = _negativeCacheUntilByKey[cacheKey];
    if (negativeCachedUntil != null) {
      if (negativeCachedUntil.isAfter(now)) {
        AppLogger.debug(
          'Skipping fetch due to recent failure cache for: $url',
          subCategory: 'image_cache',
        );
        return null;
      }
      _negativeCacheUntilByKey.remove(cacheKey);
    }

    final cached = await _getCachedImageByKey(url: url, cacheKey: cacheKey);
    if (cached != null) {
      return cached;
    }

    final inFlight = _inFlightRequests[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final request = () async {
      final bytes = await fetcher();
      if (bytes != null) {
        await _cacheImageByKey(url: url, cacheKey: cacheKey, bytes: bytes);
      } else {
        _negativeCacheUntilByKey[cacheKey] = _nowProvider().add(
          Duration(minutes: AppConstants.imageFailureCacheTtlMinutes),
        );
      }
      return bytes;
    }();

    _inFlightRequests[cacheKey] = request;

    try {
      return await request;
    } finally {
      if (identical(_inFlightRequests[cacheKey], request)) {
        _inFlightRequests.remove(cacheKey);
      }
    }
  }

  Future<void> _pruneDiskCacheIfNeeded() async {
    if (_cacheDirectory == null) {
      return;
    }

    final now = _nowProvider();
    final minimumInterval = Duration(
      hours: AppConstants.imageCachePruneIntervalHours,
    );
    if (_lastPrunedAt != null &&
        now.difference(_lastPrunedAt!) < minimumInterval) {
      return;
    }

    _lastPrunedAt = now;
    await _pruneDiskCache(now: now);
  }

  Future<void> _pruneDiskCache({required DateTime now}) async {
    final directory = _cacheDirectory;
    if (directory == null || !await directory.exists()) {
      return;
    }

    final files = <io.File>[];
    try {
      final entities = await directory.list(followLinks: false).toList();
      for (final entity in entities) {
        if (entity is io.File) {
          files.add(entity);
        }
      }
    } catch (e) {
      AppLogger.error(
        'Failed to list disk cache entries',
        subCategory: 'image_cache',
        error: e,
      );
      return;
    }

    final ttl = Duration(days: AppConstants.imageDiskCacheTtlDays);
    final retained = <({io.File file, io.FileStat stat})>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        final age = now.difference(stat.modified);
        if (age > ttl) {
          await file.delete();
        } else {
          retained.add((file: file, stat: stat));
        }
      } catch (e) {
        AppLogger.error(
          'Failed to prune disk cache entry ${file.path}',
          subCategory: 'image_cache',
          error: e,
        );
      }
    }

    final maxEntries = AppConstants.imageDiskCacheMaxEntries;
    if (retained.length <= maxEntries) {
      return;
    }

    retained.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    final removeCount = retained.length - maxEntries;
    for (int i = 0; i < removeCount; i++) {
      try {
        await retained[i].file.delete();
      } catch (e) {
        AppLogger.error(
          'Failed to remove excess disk cache entry ${retained[i].file.path}',
          subCategory: 'image_cache',
          error: e,
        );
      }
    }
  }

  Future<void> clearCache() async {
    _memoryCache.clear();
    _inFlightRequests.clear();
    _negativeCacheUntilByKey.clear();

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
  Future<void> setCacheDirectoryForTesting(io.Directory directory) async {
    _cacheDirectory = directory;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _isInitialized = true;
  }

  @visibleForTesting
  Future<void> pruneDiskCacheNowForTesting({DateTime? now}) async {
    final pruneTime = now ?? _nowProvider();
    await _pruneDiskCache(now: pruneTime);
    _lastPrunedAt = pruneTime;
  }

  @visibleForTesting
  void setNowProviderForTesting(DateTime Function() nowProvider) {
    _nowProvider = nowProvider;
  }

  bool _canStoreInMemory(Uint8List bytes) {
    return bytes.lengthInBytes <= AppConstants.maxAvatarMemoryEntryBytes;
  }

  @visibleForTesting
  int get memoryEntryCountForTesting => _memoryCache.length;

  @visibleForTesting
  int get memoryBytesForTesting => _memoryCache.totalBytes;

  @visibleForTesting
  bool hasMemoryEntryForTesting(String url) {
    final cacheKey = _safeCacheKey(url);
    if (cacheKey == null) {
      return false;
    }
    return _memoryCache.containsKey(cacheKey);
  }

  @visibleForTesting
  static void reset() {
    _instance._memoryCache.clear();
    _instance._inFlightRequests.clear();
    _instance._negativeCacheUntilByKey.clear();
    _instance._cacheDirectory = null;
    _instance._isInitialized = false;
    _instance._lastPrunedAt = null;
    _instance._nowProvider = DateTime.now;
  }
}
