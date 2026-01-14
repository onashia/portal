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
