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
///
/// Note: If [V] is nullable, missing keys and null values are not distinguishable.
bool areMapsEquivalent<K, V>(
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

bool areStringMapsEquivalent(
  Map<String, String> previous,
  Map<String, String> next,
) {
  return areMapsEquivalent(previous, next);
}
