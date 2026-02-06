import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:window_manager/window_manager.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:m3e_collection/m3e_collection.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../services/notification_service.dart';
import '../utils/animation_constants.dart';
import '../utils/vrchat_image_utils.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/debug_info_card.dart';
import '../widgets/group_instance_list.dart';
import '../utils/app_logger.dart';
import '../widgets/group_selection_side_sheet.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _isSideSheetOpen = false;
  final OverlayPortalController _debugOverlayController =
      OverlayPortalController();
  final LayerLink _debugOverlayLink = LayerLink();

  void _openSideSheet() {
    if (!_isSideSheetOpen) {
      setState(() {
        _isSideSheetOpen = true;
      });
    }
  }

  void _openSideSheetForUser(String userId) {
    _openSideSheet();
    ref.read(groupMonitorProvider(userId).notifier).fetchUserGroupsIfNeeded();
  }

  void _closeSideSheet() {
    if (_isSideSheetOpen) {
      setState(() {
        _isSideSheetOpen = false;
      });
    }
  }

  void _toggleSideSheetForUser(String userId) {
    if (_isSideSheetOpen) {
      _closeSideSheet();
    } else {
      _openSideSheetForUser(userId);
    }
  }

  @override
  void initState() {
    super.initState();
    AppLogger.debug('Dashboard initialized', subCategory: 'dashboard');
    NotificationService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    final authValue = ref.watch(authProvider);
    final themeMode = ref.watch(themeProvider);

    return authValue.when(
      loading: () => Scaffold(
        body: Center(
          child: Transform.scale(
            scale: 2.0,
            child: const LoadingIndicatorM3E(
              variant: LoadingIndicatorM3EVariant.defaultStyle,
              semanticLabel: 'Loading portal',
            ),
          ),
        ),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                SizedBox(height: context.m3e.spacing.md),
                Text(
                  'An error occurred',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                SizedBox(height: context.m3e.spacing.sm),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
      data: (authState) {
        final currentUser = authState.currentUser;

        if (currentUser == null) {
          return Scaffold(
            body: Center(
              child: Transform.scale(
                scale: 2.0,
                child: const LoadingIndicatorM3E(
                  variant: LoadingIndicatorM3EVariant.defaultStyle,
                  semanticLabel: 'Loading portal',
                ),
              ),
            ),
          );
        }

        // Null-safe: currentUser is guaranteed non-null after the check above
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
              IconButtonM3E(
                icon: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                tooltip: themeMode == ThemeMode.dark
                    ? 'Light Mode'
                    : 'Dark Mode',
                variant: IconButtonM3EVariant.standard,
                size: IconButtonM3ESize.sm,
                shape: IconButtonM3EShapeVariant.round,
                onPressed: () {
                  ref.read(themeProvider.notifier).toggleTheme();
                },
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Logout',
                onPressed: () async {
                  ref
                      .read(groupMonitorProvider(userId).notifier)
                      .stopMonitoring();
                  await ref.read(authProvider.notifier).logout();
                },
              ),
            ],
          ),
          body: DragToResizeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const sheetTargetWidth = 380.0;
                const minContentWidth = 640.0;
                final totalWidth = constraints.maxWidth;
                final canDock =
                    totalWidth >= (sheetTargetWidth + minContentWidth);
                final effectiveSheetWidth = totalWidth < sheetTargetWidth
                    ? totalWidth
                    : sheetTargetWidth;
                final sideSheet = KeyedSubtree(
                  key: const ValueKey('groupSideSheet'),
                  child: GroupSelectionSideSheet(
                    userId: userId,
                    onClose: _closeSideSheet,
                  ),
                );

                final content = SizedBox.expand(
                  child: Stack(
                    children: [
                      SafeArea(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(
                            left: 24,
                            right: 24,
                            top: 24,
                            bottom: context.m3e.spacing.xxl * 4,
                          ), // 128px: space for floating action area (56px FAB + 24px margin + 48px buffer)
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 800),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildUserCard(context, currentUser),
                                  SizedBox(height: context.m3e.spacing.lg),
                                  _buildGroupMonitoringSection(
                                    context,
                                    userId,
                                    monitorState,
                                    selectedGroups,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: context.m3e.spacing.xl,
                        right: context.m3e.spacing.xl,
                        child: _buildFloatingActionArea(
                          context,
                          userId,
                          monitorState,
                          () => _toggleSideSheetForUser(userId),
                        ),
                      ),
                    ],
                  ),
                );

                return SingleMotionBuilder(
                  motion: AnimationConstants.expressiveSpatialDefault,
                  value: _isSideSheetOpen ? 1.0 : 0.0,
                  from: 0.0,
                  builder: (context, value, _) {
                    final progress = value.clamp(0.0, 1.0);
                    return _buildSideSheetLayout(
                      context: context,
                      content: content,
                      sideSheet: sideSheet,
                      sheetWidth: effectiveSheetWidth,
                      isDocked: canDock,
                      progress: progress,
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserCard(BuildContext context, CurrentUser currentUser) {
    return Padding(
      padding: EdgeInsets.all(context.m3e.spacing.lg),
      child: Row(
        children: [
          CachedImage(
            imageUrl: _getUserProfileImageUrl(currentUser),
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
          SizedBox(width: context.m3e.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentUser.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: context.m3e.spacing.xs),
                Row(
                  children: [
                    Icon(
                      _getStatusIcon(currentUser.state),
                      size: 16,
                      color: _getStatusColor(context, currentUser.state),
                    ),
                    SizedBox(width: context.m3e.spacing.sm),
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
            Text(
              'Group Monitoring',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: context.m3e.spacing.md),
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

  Widget _buildFloatingActionArea(
    BuildContext context,
    String userId,
    GroupMonitorState monitorState,
    VoidCallback onManageGroups,
  ) {
    final actions = [
      ToolbarActionM3E(
        icon: Icons.refresh,
        onPressed: () {
          ref.read(groupMonitorProvider(userId).notifier).fetchGroupInstances();
        },
        tooltip: 'Refresh Instances',
      ),
      ToolbarActionM3E(
        icon: monitorState.isMonitoring
            ? Icons.pause_circle
            : Icons.play_circle,
        onPressed: () {
          final notifier = ref.read(groupMonitorProvider(userId).notifier);
          if (monitorState.isMonitoring) {
            notifier.stopMonitoring();
          } else {
            notifier.startMonitoring();
          }
        },
        tooltip: monitorState.isMonitoring
            ? 'Stop Monitoring'
            : 'Start Monitoring',
      ),
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OverlayPortal(
          controller: _debugOverlayController,
          overlayChildBuilder: (context) {
            return Positioned.fill(
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _debugOverlayController.hide,
                  ),
                  CompositedTransformFollower(
                    link: _debugOverlayLink,
                    targetAnchor: Alignment.topRight,
                    followerAnchor: Alignment.bottomRight,
                    offset: Offset(0, -context.m3e.spacing.sm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: IntrinsicWidth(
                        child: Card(
                          child: DebugInfoCard(
                            monitorState: monitorState,
                            useCard: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
          child: CompositedTransformTarget(
            link: _debugOverlayLink,
            child: IntrinsicWidth(
              child: ToolbarM3E(
                actions: [
                  ...actions,
                  ToolbarActionM3E(
                    icon: Icons.info_outline,
                    onPressed: _debugOverlayController.toggle,
                    tooltip: 'Debug Info',
                  ),
                ],
                variant: ToolbarM3EVariant.tonal,
                size: ToolbarM3ESize.medium,
                shapeFamily: ToolbarM3EShapeFamily.round,
                density: ToolbarM3EDensity.regular,
                maxInlineActions: 3,
                safeArea: false,
              ),
            ),
          ),
        ),
        SizedBox(width: context.m3e.spacing.md),
        ExtendedFabM3E(
          icon: const Icon(Icons.groups),
          label: const Text('Manage Groups'),
          kind: FabM3EKind.primary,
          size: FabM3ESize.regular,
          shapeFamily: FabM3EShapeFamily.round,
          onPressed: onManageGroups,
        ),
      ],
    );
  }

  Widget _buildSideSheetLayout({
    required BuildContext context,
    required Widget content,
    required Widget sideSheet,
    required double sheetWidth,
    required bool isDocked,
    required double progress,
  }) {
    final topInset = 0.0;
    final rightInset = context.m3e.spacing.lg;
    final bottomInset = context.m3e.spacing.lg;
    final shellWidth = sheetWidth + rightInset;
    final clampedProgress = progress.clamp(0.0, 1.0);
    final opacityProgress = Curves.easeOut.transform(
      (clampedProgress * 2).clamp(0.0, 1.0),
    );
    const minVisibleOpacity = 0.02;
    final isVisible = opacityProgress > minVisibleOpacity;
    final dockedPadding = isDocked ? shellWidth * clampedProgress : 0.0;
    final sheetTranslateX = shellWidth * (1 - clampedProgress);

    return SizedBox.expand(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(right: dockedPadding),
            child: content,
          ),
          if (!isDocked && isVisible)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeSideSheet,
                behavior: HitTestBehavior.opaque,
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          Positioned(
            right: 0,
            top: topInset,
            bottom: 0,
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(sheetTranslateX, 0),
                child: SizedBox(
                  width: shellWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1.0,
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: rightInset,
                        bottom: bottomInset,
                      ),
                      child: IgnorePointer(
                        ignoring: !isVisible,
                        child: Opacity(
                          opacity: opacityProgress,
                          child: sideSheet,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
        return Theme.of(context).colorScheme.primary;
      case UserState.offline:
        return Theme.of(context).colorScheme.outline;
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
