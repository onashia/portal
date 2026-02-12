import 'package:flutter_test/flutter_test.dart';
import 'package:portal/utils/lru_cache.dart';

void main() {
  group('LRUCache', () {
    group('basic operations', () {
      test('put and get returns stored value', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.put('key1', 100);
        expect(cache.get('key1'), 100);
      });

      test('get returns null for non-existent key', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        expect(cache.get('nonexistent'), isNull);
      });

      test('length returns correct count', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        expect(cache.length, 0);
        cache.put('key1', 100);
        expect(cache.length, 1);
        cache.put('key2', 200);
        expect(cache.length, 2);
      });
    });

    group('update operations', () {
      test('put updates existing key value', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.put('key1', 100);
        cache.put('key1', 200);
        expect(cache.get('key1'), 200);
        expect(cache.length, 1);
      });

      test('put on existing key marks it as recently used', () {
        final cache = LRUCache<String, int>(maxSize: 2);
        cache.put('key1', 100);
        cache.put('key2', 200);
        cache.put('key1', 150);
        cache.put('key3', 300);
        expect(cache.get('key1'), 150);
        expect(cache.get('key2'), isNull);
        expect(cache.get('key3'), 300);
      });
    });

    group('LRU behavior', () {
      test('get marks key as recently used', () {
        final cache = LRUCache<String, int>(maxSize: 2);
        cache.put('key1', 100);
        cache.put('key2', 200);
        cache.get('key1');
        cache.put('key3', 300);
        expect(cache.get('key1'), 100);
        expect(cache.get('key2'), isNull);
        expect(cache.get('key3'), 300);
      });

      test('evicts least recently used when exceeding maxSize', () {
        final cache = LRUCache<String, int>(maxSize: 2);
        cache.put('key1', 100);
        cache.put('key2', 200);
        cache.put('key3', 300);
        expect(cache.get('key1'), isNull);
        expect(cache.get('key2'), 200);
        expect(cache.get('key3'), 300);
      });

      test('maintains LRU order with multiple accesses', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);
        cache.get('a');
        cache.get('b');
        cache.put('d', 4);
        expect(cache.get('a'), 1);
        expect(cache.get('b'), 2);
        expect(cache.get('c'), isNull);
        expect(cache.get('d'), 4);
      });
    });

    group('clear operation', () {
      test('clear removes all entries', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.put('key1', 100);
        cache.put('key2', 200);
        cache.clear();
        expect(cache.length, 0);
        expect(cache.get('key1'), isNull);
        expect(cache.get('key2'), isNull);
      });

      test('clear works on empty cache', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.clear();
        expect(cache.length, 0);
      });
    });

    group('edge cases', () {
      test('handles maxSize of 1', () {
        final cache = LRUCache<String, int>(maxSize: 1);
        cache.put('key1', 100);
        expect(cache.get('key1'), 100);
        cache.put('key2', 200);
        expect(cache.get('key1'), isNull);
        expect(cache.get('key2'), 200);
        expect(cache.length, 1);
      });

      test('handles different value types', () {
        final cache = LRUCache<String, dynamic>(maxSize: 3);
        cache.put('string', 'value');
        cache.put('int', 42);
        cache.put('list', [1, 2, 3]);
        expect(cache.get('string'), 'value');
        expect(cache.get('int'), 42);
        expect(cache.get('list'), [1, 2, 3]);
      });

      test('handles integer keys', () {
        final cache = LRUCache<int, String>(maxSize: 3);
        cache.put(1, 'one');
        cache.put(2, 'two');
        expect(cache.get(1), 'one');
        expect(cache.get(2), 'two');
      });

      test('handles empty string keys', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.put('', 100);
        expect(cache.get(''), 100);
      });
    });

    group('eviction order verification', () {
      test('FIFO order when no get operations', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);
        cache.put('d', 4);
        expect(cache.get('a'), isNull);
        expect(cache.get('b'), 2);
        expect(cache.get('c'), 3);
        expect(cache.get('d'), 4);
      });

      test('updates LRU on put of existing key', () {
        final cache = LRUCache<String, int>(maxSize: 3);
        cache.put('a', 1);
        cache.put('b', 2);
        cache.put('c', 3);
        cache.put('a', 10);
        cache.put('d', 4);
        expect(cache.get('a'), 10);
        expect(cache.get('b'), isNull);
        expect(cache.get('c'), 3);
        expect(cache.get('d'), 4);
      });
    });
  });
}
