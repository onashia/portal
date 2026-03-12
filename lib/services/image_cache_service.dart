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
  Future<void> Function()? _beforeClearCacheDeleteHook;

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

  String? _resolveCacheKey(String url) {
    if (url.isEmpty) {
      return null;
    }
    return _safeCacheKey(url);
  }

  @visibleForTesting
  String getCacheKeyForTesting(String url) {
    final fileIdInfo = extractFileIdFromUrl(url);
    final bytes = utf8.encode('${fileIdInfo.fileId}_${fileIdInfo.version}');
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  bool _hasActiveNegativeCache(String cacheKey, DateTime now) {
    final negativeCachedUntil = _negativeCacheUntilByKey[cacheKey];
    return negativeCachedUntil != null && negativeCachedUntil.isAfter(now);
  }

  void _clearExpiredNegativeCache(String cacheKey, DateTime now) {
    final negativeCachedUntil = _negativeCacheUntilByKey[cacheKey];
    if (negativeCachedUntil != null && !negativeCachedUntil.isAfter(now)) {
      _negativeCacheUntilByKey.remove(cacheKey);
    }
  }

  void _recordNegativeCache(String cacheKey, DateTime now) {
    _negativeCacheUntilByKey[cacheKey] = now.add(
      Duration(minutes: AppConstants.imageFailureCacheTtlMinutes),
    );
  }

  Future<Uint8List?>? _getInFlightRequest(String cacheKey) {
    return _inFlightRequests[cacheKey];
  }

  void _trackInFlightRequest(String cacheKey, Future<Uint8List?> request) {
    _inFlightRequests[cacheKey] = request;
  }

  void _clearInFlightRequest(String cacheKey, Future<Uint8List?> request) {
    if (identical(_inFlightRequests[cacheKey], request)) {
      _inFlightRequests.remove(cacheKey);
    }
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

    final diskBytes = await _readDiskBytes(cacheKey);
    if (diskBytes != null) {
      if (_canStoreInMemory(diskBytes)) {
        _memoryCache.put(cacheKey, diskBytes);
      }
      AppLogger.debug('Disk cache HIT for: $url', subCategory: 'image_cache');
      return diskBytes;
    }

    AppLogger.debug(
      'Complete cache MISS for: $url, will fetch from API',
      subCategory: 'image_cache',
    );
    return null;
  }

  Future<Uint8List?> getCachedImage(String url) async {
    final cacheKey = _resolveCacheKey(url);
    if (cacheKey == null) {
      return null;
    }

    return _getCachedImageByKey(url: url, cacheKey: cacheKey);
  }

  Future<void> _cacheImageByKey({
    required String cacheKey,
    required Uint8List bytes,
  }) async {
    if (_canStoreInMemory(bytes)) {
      _memoryCache.put(cacheKey, bytes);
    }
    _negativeCacheUntilByKey.remove(cacheKey);

    await _initialize();
    await _writeDiskBytes(cacheKey, bytes);

    await _pruneDiskCacheIfNeeded();
  }

  Future<void> cacheImage(String url, Uint8List bytes) async {
    final cacheKey = _resolveCacheKey(url);
    if (cacheKey == null) {
      return;
    }

    await _cacheImageByKey(cacheKey: cacheKey, bytes: bytes);
  }

  Future<Uint8List?> getOrFetchImage(
    String url,
    Future<Uint8List?> Function() fetcher,
  ) async {
    final cacheKey = _resolveCacheKey(url);
    if (cacheKey == null) {
      return null;
    }

    final now = _nowProvider();
    if (_hasActiveNegativeCache(cacheKey, now)) {
      AppLogger.debug(
        'Skipping fetch due to recent failure cache for: $url',
        subCategory: 'image_cache',
      );
      return null;
    }
    _clearExpiredNegativeCache(cacheKey, now);

    final cached = await _getCachedImageByKey(url: url, cacheKey: cacheKey);
    if (cached != null) {
      return cached;
    }

    final inFlight = _getInFlightRequest(cacheKey);
    if (inFlight != null) {
      return inFlight;
    }

    final request = () async {
      final bytes = await fetcher();
      if (bytes != null) {
        await _cacheImageByKey(cacheKey: cacheKey, bytes: bytes);
      } else {
        _recordNegativeCache(cacheKey, _nowProvider());
      }
      return bytes;
    }();

    _trackInFlightRequest(cacheKey, request);

    try {
      return await request;
    } finally {
      _clearInFlightRequest(cacheKey, request);
    }
  }

  Future<void> _pruneDiskCacheIfNeeded() async {
    final now = _nowProvider();
    if (_shouldSkipPrune(now)) {
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

    final files = await _listCacheFiles(directory);
    if (files == null) {
      return;
    }

    final retained = await _pruneByTtl(files: files, now: now);
    await _pruneByMaxEntries(retained: retained);
  }

  io.File _cacheFile(String cacheKey) {
    return io.File('${_cacheDirectory!.path}/$cacheKey');
  }

  Future<Uint8List?> _readDiskBytes(String cacheKey) async {
    if (_cacheDirectory == null) {
      return null;
    }

    try {
      final file = _cacheFile(cacheKey);
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } catch (e) {
      AppLogger.error(
        'Failed to read from disk cache for key $cacheKey',
        subCategory: 'image_cache',
        error: e,
      );
      return null;
    }
  }

  Future<void> _writeDiskBytes(String cacheKey, Uint8List bytes) async {
    if (_cacheDirectory == null) {
      return;
    }

    try {
      final file = _cacheFile(cacheKey);
      await file.writeAsBytes(bytes);
    } catch (e) {
      AppLogger.error(
        'Failed to write to disk cache for key $cacheKey',
        subCategory: 'image_cache',
        error: e,
      );
    }
  }

  bool _shouldSkipPrune(DateTime now) {
    if (_cacheDirectory == null) {
      return true;
    }

    final minimumInterval = Duration(
      hours: AppConstants.imageCachePruneIntervalHours,
    );
    return _lastPrunedAt != null &&
        now.difference(_lastPrunedAt!) < minimumInterval;
  }

  Future<List<io.File>?> _listCacheFiles(io.Directory directory) async {
    final files = <io.File>[];
    try {
      final entities = await directory.list(followLinks: false).toList();
      for (final entity in entities) {
        if (entity is io.File) {
          files.add(entity);
        }
      }
      return files;
    } catch (e) {
      AppLogger.error(
        'Failed to list disk cache entries',
        subCategory: 'image_cache',
        error: e,
      );
      return null;
    }
  }

  Future<List<({io.File file, io.FileStat stat})>> _pruneByTtl({
    required List<io.File> files,
    required DateTime now,
  }) async {
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
    return retained;
  }

  Future<void> _pruneByMaxEntries({
    required List<({io.File file, io.FileStat stat})> retained,
  }) async {
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
    _lastPrunedAt = null;

    final directory = _cacheDirectory;
    if (directory == null) {
      return;
    }

    try {
      await _beforeClearCacheDeleteHook?.call();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e) {
      AppLogger.error(
        'Failed to delete disk cache directory: $e',
        subCategory: 'image_cache',
        error: e,
      );
    }

    try {
      await directory.create(recursive: true);
    } catch (e) {
      AppLogger.error(
        'Failed to recreate disk cache directory: $e',
        subCategory: 'image_cache',
        error: e,
      );
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

  @visibleForTesting
  void setBeforeClearCacheDeleteHookForTesting(Future<void> Function()? hook) {
    _beforeClearCacheDeleteHook = hook;
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
    final cacheKey = _resolveCacheKey(url);
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
    _instance._beforeClearCacheDeleteHook = null;
  }
}
