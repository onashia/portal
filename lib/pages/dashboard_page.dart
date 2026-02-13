import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:motor/motor.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../providers/theme_provider.dart';
import '../services/notification_service.dart';
import '../utils/animation_constants.dart';
import '../utils/app_logger.dart';
import '../utils/error_utils.dart';
import '../widgets/common/empty_state.dart';
import '../constants/icon_sizes.dart';
import '../widgets/custom_title_bar.dart';
import '../constants/ui_constants.dart';
import '../widgets/dashboard/dashboard_action_area.dart';
import '../widgets/dashboard/dashboard_cards.dart';
import '../widgets/dashboard/dashboard_side_sheet_layout.dart';
import '../widgets/dashboard/dashboard_user_card.dart';
import '../widgets/group_selection_side_sheet.dart';

enum DashboardAuthViewState { loading, error, handoff, ready }

@visibleForTesting
DashboardAuthViewState resolveDashboardAuthViewState({
  required AuthAsyncMeta authMeta,
  required AuthStatus? authStatus,
  required CurrentUser? currentUser,
}) {
  if (authMeta.isLoading) {
    return DashboardAuthViewState.loading;
  }

  if (authMeta.hasError) {
    return DashboardAuthViewState.error;
  }

  final isRedirectingUnauthenticated =
      currentUser == null &&
      (authStatus == AuthStatus.initial ||
          authStatus == AuthStatus.unauthenticated);
  if (isRedirectingUnauthenticated) {
    return DashboardAuthViewState.handoff;
  }

  if (currentUser == null) {
    return DashboardAuthViewState.loading;
  }

  return DashboardAuthViewState.ready;
}

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _isSideSheetOpen = false;

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
    final authMeta = ref.watch(authAsyncMetaProvider);
    final authStatus = ref.watch(authStatusProvider);
    final currentUser = ref.watch(authCurrentUserProvider);
    final themeMode = ref.watch(themeProvider);
    final authViewState = resolveDashboardAuthViewState(
      authMeta: authMeta,
      authStatus: authStatus,
      currentUser: currentUser,
    );

    if (authViewState == DashboardAuthViewState.loading) {
      return Scaffold(
        body: Center(
          child: Transform.scale(
            scale: UiConstants.dashboardLoadingScale,
            child: const LoadingIndicatorM3E(
              variant: LoadingIndicatorM3EVariant.defaultStyle,
              semanticLabel: 'Loading portal',
            ),
          ),
        ),
      );
    }

    if (authViewState == DashboardAuthViewState.error) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: CustomTitleBar(
          title: 'portal.',
          icon: Icons.tonality,
          actions: [
            IconButton(
              icon: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: IconSizes.xs,
              ),
              tooltip: themeMode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
              onPressed: () {
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
          ],
        ),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'An error occurred',
          message: formatUiErrorMessage(authMeta.error),
          iconColor: scheme.error,
        ),
      );
    }

    if (authViewState == DashboardAuthViewState.handoff) {
      return const SizedBox.shrink();
    }

    final userId = currentUser!.id;

    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        actions: [
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: IconSizes.xs,
            ),
            tooltip: themeMode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
            onPressed: () {
              ref.read(themeProvider.notifier).toggleTheme();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: IconSizes.xs),
            tooltip: 'Logout',
            onPressed: () async {
              ref.read(groupMonitorProvider(userId).notifier).stopMonitoring();
              await ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: DragToResizeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final effectiveSheetWidth =
                totalWidth < UiConstants.dashboardSheetTargetWidth
                ? totalWidth
                : UiConstants.dashboardSheetTargetWidth;
            final horizontalPadding = context.m3e.spacing.xxl * 2;
            final maxWidth = math.max(
              0.0,
              math.min(
                UiConstants.dashboardMaxContentWidth,
                constraints.maxWidth - (horizontalPadding * 2),
              ),
            );
            final canShowSideBySide =
                maxWidth >=
                (UiConstants.dashboardMinGroupCardWidth +
                    UiConstants.dashboardMinEventsCardWidth +
                    context.m3e.spacing.lg);
            final sideBySideBottomPadding = context.m3e.spacing.xxl * 3;
            final stackedBottomPadding = context.m3e.spacing.xl;
            final contentBottomPadding = canShowSideBySide
                ? sideBySideBottomPadding
                : stackedBottomPadding;
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
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: horizontalPadding,
                        right: horizontalPadding,
                        top: context.m3e.spacing.xl,
                        bottom: contentBottomPadding,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DashboardUserCard(currentUser: currentUser),
                              SizedBox(height: context.m3e.spacing.lg),
                              Expanded(
                                child: DashboardCards(
                                  userId: userId,
                                  canShowSideBySide: canShowSideBySide,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                return Stack(
                  children: [
                    DashboardSideSheetLayout(
                      content: content,
                      sideSheet: sideSheet,
                      sheetWidth: effectiveSheetWidth,
                      progress: progress,
                      onClose: _closeSideSheet,
                    ),
                    Positioned(
                      bottom: context.m3e.spacing.xl,
                      right: context.m3e.spacing.xl,
                      child: DashboardActionArea(
                        userId: userId,
                        onManageGroups: () => _toggleSideSheetForUser(userId),
                        sheetWidth: effectiveSheetWidth,
                        progress: progress,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
