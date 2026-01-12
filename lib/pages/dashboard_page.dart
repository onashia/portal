import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/custom_title_bar.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final currentUser = authState.currentUser;
    final themeMode = ref.watch(themeProvider);

    if (currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: CustomTitleBar(
        title: 'Dashboard',
        actions: [
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            ),
            tooltip: themeMode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
            onPressed: () {
              ref.read(themeProvider.notifier).toggleTheme();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
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
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
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
                        child: ClipOval(
                          child: Image.network(
                            currentUser.currentAvatarThumbnailImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.person,
                                  size: 28,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentUser.displayName,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  _getStatusIcon(currentUser.state),
                                  size: 16,
                                  color: _getStatusColor(
                                    context,
                                    currentUser.state,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getStatusText(currentUser.state),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: _getStatusColor(
                                          context,
                                          currentUser.state,
                                        ),
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
              ),
            ),
          ),
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
        return Colors.green;
      case UserState.offline:
        return Colors.grey;
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
