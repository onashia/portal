import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../../providers/group_calendar_provider.dart';
import '../../providers/group_monitor_provider.dart';
import '../debug_info_card.dart';

class DashboardActionArea extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onManageGroups;
  final double sheetWidth;
  final double progress;

  const DashboardActionArea({
    super.key,
    required this.userId,
    required this.onManageGroups,
    required this.sheetWidth,
    required this.progress,
  });

  @override
  ConsumerState<DashboardActionArea> createState() =>
      _DashboardActionAreaState();
}

class _DashboardActionAreaState extends ConsumerState<DashboardActionArea> {
  final OverlayPortalController _debugOverlayController =
      OverlayPortalController();
  final LayerLink _debugOverlayLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    final autoInviteEnabled = ref.watch(
      groupMonitorProvider(
        widget.userId,
      ).select((monitorState) => monitorState.autoInviteEnabled),
    );

    final actions = [
      ToolbarActionM3E(
        icon: autoInviteEnabled ? Icons.event_available : Icons.event_busy,
        onPressed: () {
          ref
              .read(groupMonitorProvider(widget.userId).notifier)
              .toggleAutoInvite();
        },
        tooltip: autoInviteEnabled ? 'Auto-Invite On' : 'Auto-Invite Off',
        label: autoInviteEnabled ? 'Auto-Invite On' : 'Auto-Invite Off',
      ),
      ToolbarActionM3E(
        icon: Icons.refresh,
        onPressed: () {
          ref
              .read(groupMonitorProvider(widget.userId).notifier)
              .requestRefresh(immediate: true);
          ref
              .read(groupCalendarProvider(widget.userId).notifier)
              .requestRefresh(immediate: true);
        },
        tooltip: 'Refresh Dashboard',
      ),
    ];

    return Padding(
      padding: EdgeInsets.only(right: widget.sheetWidth * widget.progress),
      child: Row(
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
                              userId: widget.userId,
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
                  maxInlineActions: 5,
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
            onPressed: widget.onManageGroups,
          ),
        ],
      ),
    );
  }
}
