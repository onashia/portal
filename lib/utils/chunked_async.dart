import 'dart:math' as math;

/// Runs [operation] over [items] in deterministic chunks.
///
/// Results preserve the original item order.
Future<List<TOutput>> runInChunks<TInput, TOutput>({
  required List<TInput> items,
  required Future<TOutput> Function(TInput item) operation,
  required int maxConcurrent,
}) async {
  if (maxConcurrent < 1) {
    throw ArgumentError.value(
      maxConcurrent,
      'maxConcurrent',
      'must be at least 1',
    );
  }

  final results = <TOutput>[];
  for (int start = 0; start < items.length; start += maxConcurrent) {
    final end = math.min(start + maxConcurrent, items.length);
    final chunk = items.sublist(start, end);
    final chunkResults = await Future.wait(chunk.map(operation));
    results.addAll(chunkResults);
  }

  return results;
}
