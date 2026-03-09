import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:motor/motor.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/icon_sizes.dart';
import '../constants/ui_constants.dart';
import '../providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../providers/group_monitor_storage.dart';
import '../utils/animation_constants.dart';
import '../utils/app_logger.dart';
import '../utils/error_utils.dart';
import '../widgets/auth/auth_page_shell.dart';
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

@visibleForTesting
Widget buildDashboardHandoffScaffold() {
  return const Scaffold(body: SizedBox.expand());
}

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _isSideSheetOpen = false;

  @override
  void initState() {
    super.initState();
    AppLogger.debug('Dashboard initialized', subCategory: 'dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final authMeta = ref.watch(authAsyncMetaProvider);
    final authStatus = ref.watch(authStatusProvider);
    final currentUser = ref.watch(authCurrentUserProvider);
    final authViewState = resolveDashboardAuthViewState(
      authMeta: authMeta,
      authStatus: authStatus,
      currentUser: currentUser,
    );

    if (authViewState == DashboardAuthViewState.loading) {
      return _buildLoadingScaffold();
    }

    if (authViewState == DashboardAuthViewState.error) {
      return _buildErrorScaffold(context, authMeta);
    }

    if (authViewState == DashboardAuthViewState.handoff) {
      return buildDashboardHandoffScaffold();
    }

    return _buildReadyScaffold(context, currentUser!);
  }

  Widget _buildLoadingScaffold() {
    return AuthLoadingScaffold(
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

  Widget _buildErrorScaffold(BuildContext context, AuthAsyncMeta authMeta) {
    return AuthErrorScaffold(message: formatUiErrorMessage(authMeta.error));
  }

  Widget _buildReadyScaffold(BuildContext context, CurrentUser currentUser) {
    final userId = currentUser.id;

    return AuthPageScaffold(
      actions: [_buildLogoutAction(userId)],
      body: _buildDashboardBody(context, currentUser, userId),
    );
  }

  Widget _buildDashboardBody(
    BuildContext context,
    CurrentUser currentUser,
    String userId,
  ) {
    return DragToResizeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layoutData = _resolveLayoutData(context, constraints);
          final sideSheet = KeyedSubtree(
            key: const ValueKey('groupSideSheet'),
            child: GroupSelectionSideSheet(
              userId: userId,
              onClose: _closeSideSheet,
            ),
          );
          final content = _buildDashboardContent(
            context,
            currentUser,
            userId,
            layoutData,
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
                    sheetWidth: layoutData.effectiveSheetWidth,
                    progress: progress,
                    onClose: _closeSideSheet,
                  ),
                  Positioned(
                    bottom: context.m3e.spacing.xl,
                    right: context.m3e.spacing.xl,
                    child: DashboardActionArea(
                      userId: userId,
                      onManageGroups: () => _toggleSideSheetForUser(userId),
                      sheetWidth: layoutData.effectiveSheetWidth,
                      progress: progress,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDashboardContent(
    BuildContext context,
    CurrentUser currentUser,
    String userId,
    _DashboardLayoutData layoutData,
  ) {
    return SizedBox.expand(
      child: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: layoutData.horizontalPadding,
                right: layoutData.horizontalPadding,
                top: context.m3e.spacing.xl,
                bottom: layoutData.contentBottomPadding,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layoutData.maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DashboardUserCard(currentUser: currentUser),
                      SizedBox(height: context.m3e.spacing.lg),
                      Expanded(
                        child: DashboardCards(
                          userId: userId,
                          canShowSideBySide: layoutData.canShowSideBySide,
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
  }

  _DashboardLayoutData _resolveLayoutData(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final spacing = context.m3e.spacing;
    final totalWidth = constraints.maxWidth;
    final effectiveSheetWidth =
        totalWidth < UiConstants.dashboardSheetTargetWidth
        ? totalWidth
        : UiConstants.dashboardSheetTargetWidth;
    final horizontalPadding = spacing.xxl * 2;
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
            spacing.lg);
    final contentBottomPadding = canShowSideBySide
        ? spacing.xxl * 3
        : spacing.xl;

    return _DashboardLayoutData(
      effectiveSheetWidth: effectiveSheetWidth,
      horizontalPadding: horizontalPadding,
      maxWidth: maxWidth,
      canShowSideBySide: canShowSideBySide,
      contentBottomPadding: contentBottomPadding,
    );
  }

  Widget _buildLogoutAction(String userId) {
    return IconButton(
      icon: const Icon(Icons.logout, size: IconSizes.xs),
      tooltip: 'Logout',
      onPressed: () => _logout(userId),
    );
  }

  Future<void> _logout(String userId) async {
    ref.read(groupMonitorProvider(userId).notifier).stopMonitoring();
    try {
      await GroupMonitorStorage.clearAll();
    } catch (e, s) {
      AppLogger.error(
        'Failed to clear group monitor storage on logout',
        subCategory: 'group_monitor',
        error: e,
        stackTrace: s,
      );
    }
    await ref.read(authProvider.notifier).logout();
    ref.invalidate(groupMonitorProvider(userId));
  }

  void _openSideSheet() {
    if (_isSideSheetOpen) {
      return;
    }
    setState(() {
      _isSideSheetOpen = true;
    });
  }

  void _openSideSheetForUser(String userId) {
    _openSideSheet();
    ref.read(groupMonitorProvider(userId).notifier).fetchUserGroupsIfNeeded();
  }

  void _closeSideSheet() {
    if (!_isSideSheetOpen) {
      return;
    }
    setState(() {
      _isSideSheetOpen = false;
    });
  }

  void _toggleSideSheetForUser(String userId) {
    if (_isSideSheetOpen) {
      _closeSideSheet();
      return;
    }
    _openSideSheetForUser(userId);
  }
}

class _DashboardLayoutData {
  const _DashboardLayoutData({
    required this.effectiveSheetWidth,
    required this.horizontalPadding,
    required this.maxWidth,
    required this.canShowSideBySide,
    required this.contentBottomPadding,
  });

  final double effectiveSheetWidth;
  final double horizontalPadding;
  final double maxWidth;
  final bool canShowSideBySide;
  final double contentBottomPadding;
}
