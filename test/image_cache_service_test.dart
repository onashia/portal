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
  });
}
