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

bool areStringMapsEquivalent(
  Map<String, String> previous,
  Map<String, String> next,
) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous.length != next.length) {
    return false;
  }

  for (final entry in previous.entries) {
    if (next[entry.key] != entry.value) {
      return false;
    }
  }

  return true;
}
