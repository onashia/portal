import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../services/notification_service.dart';
import '../utils/vrchat_image_utils.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_info_card.dart';
import '../widgets/group_avatar_stack.dart';
import '../widgets/group_instance_list.dart';
import 'group_selection_page.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _listenerSetup = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[DASHBOARD_INIT] initState() called');
    _initializeDashboard();
  }

  Future<void> _initializeDashboard() async {
    debugPrint('[DASHBOARD_INIT] _initializeDashboard() called');
    final authState = ref.read(authProvider);
    if (authState.currentUser != null) {
      final userId = authState.currentUser!.id;

      await NotificationService().initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final currentUser = authState.currentUser;
    final themeMode = ref.watch(themeProvider);

    if (!_listenerSetup && currentUser != null) {
      _listenerSetup = true;
      ref.listen<GroupMonitorState>(groupMonitorProvider(currentUser.id), (
        previous,
        next,
      ) {
        if (previous != null &&
            next.newInstances.length > previous.newInstances.length) {
          final newCount =
              next.newInstances.length - previous.newInstances.length;
          NotificationService().showNewInstanceNotification(count: newCount);
        }
      });
    }

    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final userId = currentUser.id;
    final monitorState = ref.watch(groupMonitorProvider(userId));
    final selectedGroups = monitorState.allGroups
        .where((g) => monitorState.selectedGroupIds.contains(g.groupId))
        .toList();

    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        actions: [
          if (monitorState.newInstances.isNotEmpty)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  tooltip:
                      'New instances (${monitorState.newInstances.length})',
                  onPressed: () {
                    ref
                        .read(groupMonitorProvider(userId).notifier)
                        .acknowledgeNewInstances();
                  },
                ),
                if (monitorState.newInstances.isNotEmpty)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        monitorState.newInstances.length > 9
                            ? '9+'
                            : monitorState.newInstances.length.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            ),
            tooltip: themeMode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
            onPressed: () {
              ref.read(themeProvider.notifier).toggleTheme();
            },
          ),
          if (selectedGroups.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Clear Groups',
              onPressed: () async {
                await ref
                    .read(groupMonitorProvider(userId).notifier)
                    .clearSelectedGroups();
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              ref
                  .read(groupMonitorProvider(currentUser.id).notifier)
                  .stopMonitoring();
              await ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildUserCard(context, currentUser),
                  const SizedBox(height: 24),
                  _buildGroupMonitoringSection(
                    context,
                    currentUser.id,
                    monitorState,
                    selectedGroups,
                  ),
                  const SizedBox(height: 24),
                  DebugInfoCard(monitorState: monitorState),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(BuildContext context, CurrentUser currentUser) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CachedImage(
              imageUrl: _getUserProfileImageUrl(currentUser),
              ref: ref,
              width: 56,
              height: 56,
              shape: BoxShape.circle,
              fallbackIcon: Icons.person,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentUser.displayName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _getStatusIcon(currentUser.state),
                        size: 16,
                        color: _getStatusColor(context, currentUser.state),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _getStatusText(currentUser.state),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _getStatusColor(context, currentUser.state),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getUserProfileImageUrl(CurrentUser currentUser) {
    if (currentUser.profilePicOverrideThumbnail.isNotEmpty) {
      return currentUser.profilePicOverrideThumbnail;
    }
    return currentUser.currentAvatarThumbnailImageUrl;
  }

  Widget _buildGroupMonitoringSection(
    BuildContext context,
    String userId,
    GroupMonitorState monitorState,
    List<LimitedUserGroups> selectedGroups,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Group Monitoring',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Switch(
                  value: monitorState.isMonitoring,
                  onChanged: (value) {
                    final notifier = ref.read(
                      groupMonitorProvider(userId).notifier,
                    );
                    if (value) {
                      notifier.startMonitoring();
                    } else {
                      notifier.stopMonitoring();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (selectedGroups.isNotEmpty)
                  GroupAvatarStack(
                    groups: selectedGroups,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              GroupSelectionPage(userId: userId),
                        ),
                      );
                    },
                  ),
                const Spacer(),
                IconButton.filled(
                  tooltip: selectedGroups.isEmpty
                      ? 'Add Groups'
                      : 'Manage Groups',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) =>
                            GroupSelectionPage(userId: userId),
                      ),
                    );
                  },
                  icon: Icon(
                    selectedGroups.isEmpty ? Icons.add : Icons.manage_accounts,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            GroupInstanceList(
              userId: userId,
              onRefresh: () {
                ref
                    .read(groupMonitorProvider(userId).notifier)
                    .fetchGroupInstances();
              },
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(UserState state) {
    switch (state) {
      case UserState.online:
        return Icons.circle;
      case UserState.offline:
        return Icons.offline_bolt;
      case UserState.active:
        return Icons.play_circle;
    }
  }

  Color _getStatusColor(BuildContext context, UserState state) {
    switch (state) {
      case UserState.online:
        return const Color(0xFF4CAF50);
      case UserState.offline:
        return const Color(0xFF9E9E9E);
      case UserState.active:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _getStatusText(UserState state) {
    switch (state) {
      case UserState.online:
        return 'Online';
      case UserState.offline:
        return 'Offline';
      case UserState.active:
        return 'Active';
    }
  }
}
