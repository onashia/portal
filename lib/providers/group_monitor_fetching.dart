import '../constants/app_constants.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../services/portal_request_runner_common.dart';
import '../utils/chunked_async.dart';

typedef GroupInstanceChunkResponse<T> = ({
  String groupId,
  T? response,
  bool skippedDueToCooldown,
});

typedef GroupInstanceChunkFetchResult<T> = ({
  List<GroupInstanceChunkResponse<T>> responses,
  bool interruptedByCooldown,
  Duration? cooldownRemaining,
});

Future<GroupInstanceChunkFetchResult<T>> fetchGroupInstancesChunked<T>({
  required List<String> orderedGroupIds,
  required Future<T?> Function(String groupId) fetchGroupInstances,
  required PortalCooldownTracker cooldownTracker,
  required ApiRequestLane lane,
  bool respectCooldownBetweenChunks = true,
  int maxConcurrentRequests = AppConstants.groupInstancesMaxConcurrentRequests,
}) async {
  final results = <GroupInstanceChunkResponse<T>>[];
  Duration? cooldownRemaining;

  for (
    int start = 0;
    start < orderedGroupIds.length;
    start += maxConcurrentRequests
  ) {
    final remainingCooldown = respectCooldownBetweenChunks
        ? cooldownTracker.remainingCooldown(lane)
        : null;
    if (remainingCooldown != null) {
      cooldownRemaining ??= remainingCooldown;
      final remainingGroupIds = orderedGroupIds.sublist(start);
      results.addAll(
        remainingGroupIds.map(
          (groupId) =>
              (groupId: groupId, response: null, skippedDueToCooldown: true),
        ),
      );
      break;
    }

    final chunkEnd = start + maxConcurrentRequests < orderedGroupIds.length
        ? start + maxConcurrentRequests
        : orderedGroupIds.length;
    final chunkGroupIds = orderedGroupIds.sublist(start, chunkEnd);
    // Cooldown is only checked between chunks. Requests already in-flight
    // within this chunk will complete; the next boundary check catches it.
    final chunkResults =
        await runInChunks<
          String,
          ({String groupId, T? response, bool skippedDueToCooldown})
        >(
          items: chunkGroupIds,
          maxConcurrent: maxConcurrentRequests,
          operation: (groupId) async {
            final response = await fetchGroupInstances(groupId);
            return (
              groupId: groupId,
              response: response,
              skippedDueToCooldown: false,
            );
          },
        );
    results.addAll(chunkResults);
  }

  return (
    responses: results,
    interruptedByCooldown: cooldownRemaining != null,
    cooldownRemaining: cooldownRemaining,
  );
}
