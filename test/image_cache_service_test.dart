import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:portal/constants/app_constants.dart';
import 'package:portal/services/image_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImageCacheService service;

  setUp(() {
    service = ImageCacheService();
    ImageCacheService.reset();
  });

  tearDown(() {
    ImageCacheService.reset();
  });

  group('Security - Path Traversal Prevention', () {
    test('prevents path traversal with .. sequences', () async {
      const maliciousUrl = 'https://api.vrchat.cloud/file_..%2f..%2fconfig/1';
      final cacheKey = await service.getCachedImage(maliciousUrl);
      expect(cacheKey, isNull);
    });

    test('hashes contain only safe characters', () async {
      const url = 'https://api.vrchat.cloud/file_abc123/1';
      final key = service.getCacheKeyForTesting(url);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(key), isTrue);
    });

    test('prevents URL-encoded directory traversal', () async {
      const maliciousUrl = 'https://api.vrchat.cloud/file_%2e%2e%2fsecrets/1';
      final key = service.getCacheKeyForTesting(maliciousUrl);
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(key), isTrue);
    });
  });

  group('getCacheKeyForTesting', () {
    test('produces consistent hash for same URL', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_1234567890abcdef/1';
      final key1 = service.getCacheKeyForTesting(url);
      final key2 = service.getCacheKeyForTesting(url);
      expect(key1, equals(key2));
    });

    test('produces different hash for different URLs', () async {
      const url1 = 'https://api.vrchat.cloud/api/1/file_1234567890abcdef/1';
      const url2 = 'https://api.vrchat.cloud/api/1/file_abcdef1234567890/1';
      final key1 = service.getCacheKeyForTesting(url1);
      final key2 = service.getCacheKeyForTesting(url2);
      expect(key1, isNot(equals(key2)));
    });

    test('includes version in hash', () async {
      const url1 = 'https://api.vrchat.cloud/api/1/file_1234567890/1';
      const url2 = 'https://api.vrchat.cloud/api/1/file_1234567890/2';
      final key1 = service.getCacheKeyForTesting(url1);
      final key2 = service.getCacheKeyForTesting(url2);
      expect(key1, isNot(equals(key2)));
    });

    test('handles URL-encoded fileId', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_abc%2Ddef%20ghi/1';
      final key = service.getCacheKeyForTesting(url);
      expect(key, isNotEmpty);
      expect(key.length, equals(64));
    });
  });

  group('getCachedImage', () {
    test('returns null for empty URL', () async {
      final result = await service.getCachedImage('');
      expect(result, isNull);
    });

    test('returns null for malformed URL', () async {
      const malformedUrl = 'not-a-valid-url';
      final result = await service.getCachedImage(malformedUrl);
      expect(result, isNull);
    });

    test('returns null on cache MISS', () async {
      const uncachedUrl = 'https://api.vrchat.cloud/api/1/file_uncached/1';
      final result = await service.getCachedImage(uncachedUrl);
      expect(result, isNull);
    });
  });

  group('cacheImage', () {
    test('does nothing for empty URL', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      await service.cacheImage('', bytes);
      final result = await service.getCachedImage('');
      expect(result, isNull);
    });

    test('does nothing for malformed URL', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      await service.cacheImage('not-a-url', bytes);
      final result = await service.getCachedImage('not-a-url');
      expect(result, isNull);
    });

    test('stores in memory cache', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_memory_test/1';
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      await service.cacheImage(url, bytes);
      final result = await service.getCachedImage(url);
      expect(result, equals(bytes));
    });

    test('oversized entries skip memory cache but remain on disk', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'portal_cache_large_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await service.setCacheDirectoryForTesting(tempDir);

      const url = 'https://api.vrchat.cloud/api/1/file_oversized_memory/1';
      final bytes = Uint8List(AppConstants.maxAvatarMemoryEntryBytes + 1);
      bytes[0] = 1;

      await service.cacheImage(url, bytes);

      expect(service.memoryEntryCountForTesting, 0);
      expect(service.memoryBytesForTesting, 0);
      expect(service.hasMemoryEntryForTesting(url), isFalse);

      final result = await service.getCachedImage(url);
      expect(result, equals(bytes));
      expect(service.hasMemoryEntryForTesting(url), isFalse);
      expect(service.memoryEntryCountForTesting, 0);
      expect(service.memoryBytesForTesting, 0);
    });

    test('enforces memory byte budget with LRU eviction', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'portal_cache_memory_budget_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await service.setCacheDirectoryForTesting(tempDir);

      final entrySize = AppConstants.maxAvatarMemoryEntryBytes;
      final totalEntries =
          (AppConstants.maxAvatarMemoryCacheBytes ~/ entrySize) + 1;
      final urls = <String>[];

      for (int i = 0; i < totalEntries; i++) {
        final url = 'https://api.vrchat.cloud/api/1/file_budget_$i/1';
        urls.add(url);
        final bytes = Uint8List(entrySize);
        bytes[0] = i % 255;
        await service.cacheImage(url, bytes);
      }

      expect(
        service.memoryBytesForTesting <= AppConstants.maxAvatarMemoryCacheBytes,
        isTrue,
      );
      expect(
        service.memoryEntryCountForTesting <= AppConstants.maxAvatarCacheSize,
        isTrue,
      );
      expect(service.hasMemoryEntryForTesting(urls.first), isFalse);
      expect(service.hasMemoryEntryForTesting(urls.last), isTrue);
    });
  });

  group('clearCache', () {
    test('clears memory cache', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_clear_test/1';
      final bytes = Uint8List.fromList([1, 2, 3]);
      await service.cacheImage(url, bytes);
      expect(await service.getCachedImage(url), equals(bytes));

      await service.clearCache();
      expect(await service.getCachedImage(url), isNull);
    });

    test('clears disk cache entries and recreates the directory', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'portal_cache_clear_disk_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await service.setCacheDirectoryForTesting(tempDir);

      const url = 'https://api.vrchat.cloud/api/1/file_clear_disk_test/1';
      final bytes = Uint8List(AppConstants.maxAvatarMemoryEntryBytes + 1);
      bytes[0] = 1;
      await service.cacheImage(url, bytes);

      final cacheFile = File(
        '${tempDir.path}/${service.getCacheKeyForTesting(url)}',
      );
      expect(await cacheFile.exists(), isTrue);

      await service.clearCache();

      expect(await tempDir.exists(), isTrue);
      expect(await cacheFile.exists(), isFalse);
      expect(await service.getCachedImage(url), isNull);
    });

    test('recreates the directory even when delete fails', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'portal_cache_clear_delete_failure_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await service.setCacheDirectoryForTesting(tempDir);

      service.setBeforeClearCacheDeleteHookForTesting(() async {
        throw StateError('simulated delete failure');
      });

      await expectLater(service.clearCache(), completes);

      expect(await tempDir.exists(), isTrue);
    });
  });

  group('getOrFetchImage', () {
    test('deduplicates in-flight fetches and stores bytes once', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_dedupe_test/1';
      final expected = Uint8List.fromList([9, 8, 7, 6]);
      var fetchCalls = 0;

      Future<Uint8List?> fetcher() async {
        fetchCalls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return expected;
      }

      final results = await Future.wait([
        service.getOrFetchImage(url, fetcher),
        service.getOrFetchImage(url, fetcher),
        service.getOrFetchImage(url, fetcher),
      ]);

      expect(fetchCalls, 1);
      expect(results, everyElement(equals(expected)));
      expect(await service.getCachedImage(url), equals(expected));
    });

    test('temporarily suppresses repeated fetches after failure', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_negative_cache_test/1';
      final baseTime = DateTime.utc(2026, 2, 14, 12, 0, 0);
      var now = baseTime;
      service.setNowProviderForTesting(() => now);

      var fetchCalls = 0;
      Future<Uint8List?> failingFetcher() async {
        fetchCalls += 1;
        return null;
      }

      final first = await service.getOrFetchImage(url, failingFetcher);
      final second = await service.getOrFetchImage(url, failingFetcher);

      expect(first, isNull);
      expect(second, isNull);
      expect(fetchCalls, 1);

      now = baseTime.add(
        Duration(minutes: AppConstants.imageFailureCacheTtlMinutes + 1),
      );
      await service.getOrFetchImage(url, failingFetcher);
      expect(fetchCalls, 2);
    });

    test('success clears negative cache and caches bytes', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_negative_clear_test/1';

      var fetchCalls = 0;
      Future<Uint8List?> mixedFetcher() async {
        fetchCalls += 1;
        if (fetchCalls == 1) {
          return null;
        }
        return Uint8List.fromList([4, 5, 6]);
      }

      final first = await service.getOrFetchImage(url, mixedFetcher);
      expect(first, isNull);

      service.setNowProviderForTesting(
        () => DateTime.now().add(
          Duration(minutes: AppConstants.imageFailureCacheTtlMinutes + 1),
        ),
      );
      final second = await service.getOrFetchImage(url, mixedFetcher);
      expect(second, isNotNull);
      expect(fetchCalls, 2);

      final third = await service.getOrFetchImage(url, mixedFetcher);
      expect(third, second);
      expect(fetchCalls, 2);
    });

    test('clears in-flight tracking when fetcher throws', () async {
      const url = 'https://api.vrchat.cloud/api/1/file_inflight_throw_test/1';

      var throwCalls = 0;
      Future<Uint8List?> throwingFetcher() async {
        throwCalls += 1;
        throw StateError('boom');
      }

      await expectLater(
        service.getOrFetchImage(url, throwingFetcher),
        throwsStateError,
      );

      var successCalls = 0;
      final expected = Uint8List.fromList([7, 8, 9]);
      Future<Uint8List?> successFetcher() async {
        successCalls += 1;
        return expected;
      }

      final result = await service.getOrFetchImage(url, successFetcher);
      expect(result, equals(expected));
      expect(throwCalls, 1);
      expect(successCalls, 1);
    });
  });

  group('disk cache pruning', () {
    test('removes entries older than configured TTL', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'portal_cache_ttl_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await service.setCacheDirectoryForTesting(tempDir);

      final now = DateTime.now();
      final oldFile = File('${tempDir.path}/old_entry');
      final freshFile = File('${tempDir.path}/fresh_entry');
      await oldFile.writeAsBytes([1]);
      await freshFile.writeAsBytes([2]);
      await oldFile.setLastModified(
        now.subtract(Duration(days: AppConstants.imageDiskCacheTtlDays + 1)),
      );
      await freshFile.setLastModified(now.subtract(const Duration(days: 1)));

      await service.pruneDiskCacheNowForTesting(now: now);

      expect(await oldFile.exists(), isFalse);
      expect(await freshFile.exists(), isTrue);
    });

    test('trims oldest files when entry count exceeds max', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'portal_cache_size_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await service.setCacheDirectoryForTesting(tempDir);

      final now = DateTime.now();
      final totalEntries = AppConstants.imageDiskCacheMaxEntries + 5;
      for (int i = 0; i < totalEntries; i++) {
        final file = File('${tempDir.path}/entry_$i');
        await file.writeAsBytes([i % 255]);
        await file.setLastModified(
          now.subtract(Duration(minutes: totalEntries - i)),
        );
      }

      await service.pruneDiskCacheNowForTesting(now: now);

      final remainingFiles = await tempDir
          .list(followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      expect(remainingFiles.length, AppConstants.imageDiskCacheMaxEntries);
      expect(await File('${tempDir.path}/entry_0').exists(), isFalse);
      expect(
        await File('${tempDir.path}/entry_${totalEntries - 1}').exists(),
        isTrue,
      );
    });

    test('skips prune when interval has not elapsed', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'portal_cache_prune_interval_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await service.setCacheDirectoryForTesting(tempDir);

      final now = DateTime.utc(2026, 2, 20, 12, 0, 0);
      service.setNowProviderForTesting(() => now);
      await service.pruneDiskCacheNowForTesting(now: now);

      final staleFile = File('${tempDir.path}/stale_entry');
      await staleFile.writeAsBytes([1]);
      await staleFile.setLastModified(
        now.subtract(Duration(days: AppConstants.imageDiskCacheTtlDays + 1)),
      );

      await service.cacheImage(
        'https://api.vrchat.cloud/api/1/file_prune_interval/1',
        Uint8List.fromList([1, 2, 3]),
      );

      expect(await staleFile.exists(), isTrue);
    });
  });
}
