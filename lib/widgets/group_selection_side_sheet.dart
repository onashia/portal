import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:motor/motor.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../constants/app_typography.dart';
import '../utils/animation_constants.dart';
import '../providers/group_monitor_provider.dart';
import '../utils/group_utils.dart';
import '../utils/vrchat_image_utils.dart';
import '../widgets/group_avatar_stack.dart';

class GroupSelectionSideSheet extends ConsumerStatefulWidget {
  final String userId;
  final OverlayPortalController controller;

  const GroupSelectionSideSheet({
    super.key,
    required this.userId,
    required this.controller,
  });

  @override
  ConsumerState<GroupSelectionSideSheet> createState() =>
      _GroupSelectionSideSheetState();
}

class _GroupSelectionSideSheetState
    extends ConsumerState<GroupSelectionSideSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    Future(() {
      ref
          .read(groupMonitorProvider(widget.userId).notifier)
          .fetchUserGroupsIfNeeded();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildSheetContent(context);
  }

  Widget _buildSheetContent(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const double sheetWidth = 400;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => widget.controller.hide(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: size.width,
            height: size.height,
            color: Colors.black.withValues(alpha: 0.32),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: SingleMotionBuilder(
            motion: AnimationConstants.expressiveSpatialDefault,
            value: 1.0,
            from: 0.0,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(sheetWidth * (1 - value), 0),
                child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
              );
            },
            child: _buildSheetBody(context, size),
          ),
        ),
      ],
    );
  }

  Widget _buildSheetBody(BuildContext context, Size size) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          bottomLeft: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: context.m3e.colors.shadow.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: context.m3e.colors.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      width: 400,
      height: size.height,
      constraints: const BoxConstraints(minWidth: 400, maxWidth: 400),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          minimum: EdgeInsets.only(top: context.m3e.spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _buildHeader(context),
              _buildSearchBar(context),
              Expanded(
                child: Column(
                  children: [
                    _buildSelectedGroupsSection(context),
                    Expanded(child: _buildAvailableGroupsSection(context)),
                  ],
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final monitorState = ref.watch(groupMonitorProvider(widget.userId));
    final hasSelections = monitorState.selectedGroupIds.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          indent: context.m3e.spacing.xl,
          endIndent: context.m3e.spacing.xl,
        ),
        Padding(
          padding: EdgeInsets.only(
            left: context.m3e.spacing.xl,
            right: context.m3e.spacing.xl,
            top: context.m3e.spacing.lg,
            bottom: context.m3e.spacing.xl,
          ),
          child: Row(
            children: [
              ButtonM3E(
                onPressed: () async {
                  await ref
                      .read(groupMonitorProvider(widget.userId).notifier)
                      .clearSelectedGroups();
                },
                enabled: hasSelections,
                label: const Text('Deselect All'),
                style: ButtonM3EStyle.outlined,
                size: ButtonM3ESize.sm,
                shape: ButtonM3EShape.round,
              ),
              SizedBox(width: context.m3e.spacing.lg),
              ButtonM3E(
                onPressed: () => widget.controller.hide(),
                label: const Text('Done'),
                style: ButtonM3EStyle.filled,
                size: ButtonM3ESize.sm,
                shape: ButtonM3EShape.round,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: context.m3e.spacing.xl,
        right: context.m3e.spacing.lg,
        bottom: context.m3e.spacing.lg,
      ),
      child: Row(
        children: [
          Text('Manage Groups', style: AppTypography.titleLarge),
          const Spacer(),
          IconButtonM3E(
            icon: const Icon(Icons.close),
            onPressed: () => widget.controller.hide(),
            tooltip: 'Close',
            variant: IconButtonM3EVariant.standard,
            size: IconButtonM3ESize.sm,
            shape: IconButtonM3EShapeVariant.round,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: context.m3e.spacing.xl,
        right: context.m3e.spacing.xl,
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search groups...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
          border: OutlineInputBorder(
            borderRadius: context.m3e.shapes.round.md,
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: context.m3e.shapes.round.md,
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: context.m3e.spacing.lg,
            vertical: context.m3e.spacing.sm,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedGroupsSection(BuildContext context) {
    final monitorState = ref.watch(groupMonitorProvider(widget.userId));
    final selectedGroups = monitorState.allGroups
        .where((g) => monitorState.selectedGroupIds.contains(g.groupId))
        .toList();

    if (selectedGroups.isEmpty) {
      return _buildEmptySelectedState(context);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: context.m3e.spacing.xl,
            right: context.m3e.spacing.xl,
            top: context.m3e.spacing.lg,
          ),
          child: Row(
            children: [
              Text('Selected Groups', style: AppTypography.titleMedium),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: context.m3e.spacing.xl,
            right: context.m3e.spacing.xl,
          ),
          child: _buildAvatarStack(context, selectedGroups),
        ),
      ],
    );
  }

  Widget _buildAvatarStack(
    BuildContext context,
    List<LimitedUserGroups> groups,
  ) {
    return GroupAvatarStack(groups: groups);
  }

  Widget _buildEmptySelectedState(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.m3e.spacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.groups,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(height: context.m3e.spacing.lg),
          Text('No groups selected', style: AppTypography.bodyLarge),
        ],
      ),
    );
  }

  Widget _buildAvailableGroupsSection(BuildContext context) {
    final monitorState = ref.watch(groupMonitorProvider(widget.userId));
    final filteredGroups = _filterGroups(monitorState.allGroups);
    final selectedIds = monitorState.selectedGroupIds;

    final content = monitorState.isLoading
        ? _buildLoadingAvailableState(context)
        : filteredGroups.isEmpty
        ? _buildEmptyAvailableState(context)
        : _buildAvailableGroupsList(context, filteredGroups, selectedIds);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: context.m3e.spacing.xl,
            right: context.m3e.spacing.xl,
            top: context.m3e.spacing.lg,
          ),
          child: Row(
            children: [
              Text('Available Groups', style: AppTypography.titleMedium),
              SizedBox(width: context.m3e.spacing.sm),
              Text(
                '(${filteredGroups.length})',
                style: AppTypography.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  List<LimitedUserGroups> _filterGroups(List<LimitedUserGroups> allGroups) {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) {
      return allGroups;
    }

    return allGroups.where((group) {
      final name = (group.name ?? '').toLowerCase();
      final discriminator = (group.discriminator ?? '').toLowerCase();
      return name.contains(query) || discriminator.contains(query);
    }).toList();
  }

  Widget _buildAvailableGroupsList(
    BuildContext context,
    List<LimitedUserGroups> groups,
    Set<String> selectedIds,
  ) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        left: context.m3e.spacing.xl,
        right: context.m3e.spacing.xl,
      ),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final isSelected = selectedIds.contains(group.groupId);
        return Padding(
          padding: EdgeInsets.only(bottom: context.m3e.spacing.md),
          child: _buildGroupListItem(context, group, isSelected),
        );
      },
    );
  }

  Widget _buildGroupListItem(
    BuildContext context,
    LimitedUserGroups group,
    bool isSelected,
  ) {
    final memberCount = group.memberCount ?? 0;

    return Material(
      color: isSelected
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.5)
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: context.m3e.shapes.round.md,
      child: InkWell(
        onTap: () {
          if (group.groupId != null) {
            ref
                .read(groupMonitorProvider(widget.userId).notifier)
                .toggleGroupSelection(group.groupId!);
          }
        },
        borderRadius: context.m3e.shapes.round.md,
        child: Padding(
          padding: EdgeInsets.all(context.m3e.spacing.md),
          child: Row(
            children: [
              _buildGroupAvatar(context, group),
              SizedBox(width: context.m3e.spacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name ?? 'Unknown Group',
                      style: AppTypography.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: context.m3e.spacing.sm),
                    Text(
                      '$memberCount members',
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupAvatar(BuildContext context, LimitedUserGroups group) {
    final hasImage = group.iconUrl != null && group.iconUrl!.isNotEmpty;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasImage ? null : GroupUtils.getAvatarColor(group),
      ),
      child: ClipOval(
        child: CachedImage(
          imageUrl: hasImage ? group.iconUrl! : '',
          width: 48,
          height: 48,
          fallbackWidget: hasImage
              ? null
              : Center(
                  child: Text(
                    GroupUtils.getInitials(group),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
          showLoadingIndicator: false,
        ),
      ),
    );
  }

  Widget _buildLoadingAvailableState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicatorM3E(
              variant: LoadingIndicatorM3EVariant.defaultStyle,
              semanticLabel: 'Loading available groups',
            ),
            SizedBox(height: context.m3e.spacing.lg),
            Text(
              'Loading available groups...',
              style: context.m3e.typography.base.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyAvailableState(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: context.m3e.spacing.lg),
            Text(
              _searchQuery.isEmpty
                  ? 'No groups found'
                  : 'No groups match "$_searchQuery"',
              style: AppTypography.bodyLarge,
            ),
            SizedBox(height: context.m3e.spacing.sm),
            Text(
              'You are not a member of any groups',
              style: AppTypography.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
