import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/group_monitor_provider.dart';
import 'group_instance_timeline.dart';

class GroupInstanceList extends ConsumerWidget {
  final String userId;
  final VoidCallback onRefresh;

  const GroupInstanceList({
    super.key,
    required this.userId,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGroupIds = ref.watch(
      groupMonitorSelectedGroupIdsProvider(userId),
    );

    if (selectedGroupIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return GroupInstanceTimeline(userId: userId, onRefresh: onRefresh);
  }
}
