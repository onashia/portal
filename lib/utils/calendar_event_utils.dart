/// Returns the start of the local day for [day].
DateTime startOfLocalDay(DateTime day) {
  final local = day.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Returns the inclusive end of the local day for [day].
DateTime endOfLocalDay(DateTime day) {
  return startOfLocalDay(
    day,
  ).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
}

/// Whether a [start]..[end] window overlaps the local day containing [day].
bool overlapsLocalDay({
  required DateTime start,
  required DateTime end,
  required DateTime day,
}) {
  if (end.isBefore(start)) {
    return false;
  }

  final startLocal = start.toLocal();
  final endLocal = end.toLocal();
  final dayStart = startOfLocalDay(day);
  final dayEnd = endOfLocalDay(day);

  return !endLocal.isBefore(dayStart) && !startLocal.isAfter(dayEnd);
}
