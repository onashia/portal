import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
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
}
