/// Checks if two lists are equivalent using default or custom equality.
///
/// Uses default `==` equality unless [equals] is provided.
bool areListsEquivalent<T>(
  List<T>? previous,
  List<T>? next, {
  bool Function(T previous, T next)? equals,
}) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous == null || next == null) {
    return previous == null && next == null;
  }
  if (previous.length != next.length) {
    return false;
  }

  final itemEquals = equals ?? (T a, T b) => a == b;
  for (int i = 0; i < previous.length; i++) {
    if (!itemEquals(previous[i], next[i])) {
      return false;
    }
  }
  return true;
}

/// Checks if two maps are equivalent using default or custom equality.
bool areMapsEquivalent<K, V extends Object>(
  Map<K, V> previous,
  Map<K, V> next, {
  bool Function(V previous, V next)? valueEquals,
}) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous.length != next.length) {
    return false;
  }

  for (final entry in previous.entries) {
    final nextValue = next[entry.key];
    if (nextValue == null) {
      return false;
    }

    final equals = valueEquals ?? (V a, V b) => a == b;
    if (!equals(entry.value, nextValue)) {
      return false;
    }
  }

  return true;
}
