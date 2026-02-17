import 'dart:collection';

class LRUCache<K, V> {
  final int maxSize;
  final Map<K, _CacheNode<K, V>> _cache = {};
  // LinkedHashMap maintains insertion order, enabling LRU tracking
  final LinkedHashMap<K, _CacheNode<K, V>> _lru = LinkedHashMap();

  LRUCache({required this.maxSize});

  V? get(K key) {
    final node = _cache[key];
    if (node != null) {
      // Move to end to mark as recently used
      _lru.remove(key);
      _lru[key] = node;
      return node.value;
    }
    return null;
  }

  void put(K key, V value) {
    final node = _CacheNode(key, value);

    if (_cache.containsKey(key)) {
      // Update existing: remove and re-add to mark as recently used
      _lru.remove(key);
      _cache.remove(key);
    } else if (_lru.length >= maxSize) {
      // Evict least recently used item (first in LinkedHashMap)
      final oldestKey = _lru.keys.first;
      _lru.remove(oldestKey);
      _cache.remove(oldestKey);
    }

    _cache[key] = node;
    _lru[key] = node;
  }

  void clear() {
    _cache.clear();
    _lru.clear();
  }

  int get length => _lru.length;
}

class _CacheNode<K, V> {
  final K key;
  final V value;

  _CacheNode(this.key, this.value);
}

class ByteBudgetLRUCache<K, V> {
  final int maxEntries;
  final int maxBytes;
  final int Function(V value) sizeOf;
  // Keep dual structures for clear separation:
  // - _cache provides O(1) key lookups
  // - _lru tracks recency order for eviction
  final Map<K, _ByteBudgetCacheNode<K, V>> _cache = {};
  final LinkedHashMap<K, _ByteBudgetCacheNode<K, V>> _lru = LinkedHashMap();
  int _totalBytes = 0;

  ByteBudgetLRUCache({
    required this.maxEntries,
    required this.maxBytes,
    required this.sizeOf,
  }) {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be at least 1');
    }
    if (maxBytes < 1) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be at least 1');
    }
  }

  V? get(K key) {
    final node = _cache[key];
    if (node == null) {
      return null;
    }

    _lru.remove(key);
    _lru[key] = node;
    return node.value;
  }

  bool containsKey(K key) => _cache.containsKey(key);

  void put(K key, V value) {
    final bytes = sizeOf(value);
    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'sizeOf(value)', 'must be >= 0');
    }

    final existing = _cache[key];
    if (existing != null) {
      _cache.remove(key);
      _lru.remove(key);
      _totalBytes -= existing.byteSize;
    }

    final node = _ByteBudgetCacheNode(key, value, bytes);
    _cache[key] = node;
    _lru[key] = node;
    _totalBytes += bytes;

    _evictUntilWithinBudget();
    _assertInternalInvariants();
  }

  void _evictUntilWithinBudget() {
    while ((_lru.length > maxEntries || _totalBytes > maxBytes) &&
        _lru.isNotEmpty) {
      final oldestKey = _lru.keys.first;
      final evicted = _lru.remove(oldestKey);
      if (evicted != null) {
        _cache.remove(oldestKey);
        _totalBytes -= evicted.byteSize;
      }
    }

    // Defensive safety net in case future bookkeeping changes introduce drift.
    if (_totalBytes < 0) {
      _totalBytes = 0;
    }

    _assertInternalInvariants();
  }

  void clear() {
    _cache.clear();
    _lru.clear();
    _totalBytes = 0;
    _assertInternalInvariants();
  }

  int get length => _lru.length;

  int get totalBytes => _totalBytes;

  void _assertInternalInvariants() {
    assert(() {
      if (_totalBytes < 0) {
        throw StateError('_totalBytes must never be negative');
      }
      if (_cache.length != _lru.length) {
        throw StateError(
          'Cache length mismatch: _cache=${_cache.length}, _lru=${_lru.length}',
        );
      }
      if (_cache.keys.toSet().length != _cache.length ||
          _lru.keys.toSet().length != _lru.length) {
        throw StateError('Duplicate keys detected in cache internals');
      }
      for (final key in _cache.keys) {
        if (!_lru.containsKey(key)) {
          throw StateError('Missing key in _lru for key=$key');
        }
      }
      for (final key in _lru.keys) {
        if (!_cache.containsKey(key)) {
          throw StateError('Missing key in _cache for key=$key');
        }
      }
      final recomputedBytes = _cache.values.fold<int>(0, (sum, node) {
        if (node.byteSize < 0) {
          throw StateError('Negative node byteSize for key=${node.key}');
        }
        return sum + node.byteSize;
      });
      if (recomputedBytes != _totalBytes) {
        throw StateError(
          'Byte accounting mismatch: expected $recomputedBytes, actual $_totalBytes',
        );
      }
      return true;
    }());
  }
}

class _ByteBudgetCacheNode<K, V> {
  final K key;
  final V value;
  final int byteSize;

  _ByteBudgetCacheNode(this.key, this.value, this.byteSize);
}
