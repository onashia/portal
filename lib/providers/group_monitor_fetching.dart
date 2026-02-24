import '../constants/app_constants.dart';
import '../utils/chunked_async.dart';

Future<List<({String groupId, T? response})>> fetchGroupInstancesChunked<T>({
  required List<String> orderedGroupIds,
  required Future<T?> Function(String groupId) fetchGroupInstances,
  int maxConcurrentRequests = AppConstants.groupInstancesMaxConcurrentRequests,
}) async {
  return runInChunks<String, ({String groupId, T? response})>(
    items: orderedGroupIds,
    maxConcurrent: maxConcurrentRequests,
    operation: (groupId) async {
      final response = await fetchGroupInstances(groupId);
      return (groupId: groupId, response: response);
    },
  );
}
