import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../providers/group_monitor_provider.dart';
import '../theme/side_sheet_theme.dart';
import 'group_selection/group_avatar.dart';
import 'group_selection/groups_empty_state.dart';
import 'group_selection/groups_loading_state.dart';
import 'inputs/app_text_field.dart';

class GroupSelectionSideSheet extends ConsumerStatefulWidget {
  const GroupSelectionSideSheet({
    super.key,
    required this.userId,
    required this.onClose,
  });

  final String userId;
  final VoidCallback onClose;

  @override
  ConsumerState<GroupSelectionSideSheet> createState() =>
      _GroupSelectionSideSheetState();
}

class _GroupSelectionSideSheetState
    extends ConsumerState<GroupSelectionSideSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

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
    if (query == _searchQuery) {
      return;
    }

    setState(() {
      _searchQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectionData = _watchSelectionData();
    return _buildSheetBody(context, selectionData);
  }

  _GroupSelectionData _watchSelectionData() {
    final provider = groupMonitorProvider(widget.userId);
    return _GroupSelectionData(
      allGroups: ref.watch(provider.select((state) => state.allGroups)),
      selectedIds: ref.watch(
        provider.select((state) => state.selectedGroupIds),
      ),
      isLoading: ref.watch(provider.select((state) => state.isLoading)),
    );
  }

  Widget _buildSheetBody(BuildContext context, _GroupSelectionData data) {
    final sideSheetTheme = Theme.of(context).extension<SideSheetTheme>()!;
    final sideSheetShape = RoundedRectangleBorder(
      borderRadius: context.m3e.shapes.round.md,
    ).copyWith(side: BorderSide(color: sideSheetTheme.outlineColor));

    return Card(
      margin: EdgeInsets.zero,
      color: sideSheetTheme.containerColor,
      elevation: sideSheetTheme.elevation,
      shadowColor: sideSheetTheme.shadowColor,
      shape: sideSheetShape,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: double.infinity,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeaderSection(context),
              SizedBox(height: context.m3e.spacing.md),
              Expanded(child: _buildAvailableGroupsSection(context, data)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context) {
    final m3e = context.m3e;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: m3e.spacing.xl,
        right: m3e.spacing.xl,
        top: m3e.spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButtonM3E(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onClose,
                tooltip: 'Back',
                variant: IconButtonM3EVariant.standard,
                size: IconButtonM3ESize.sm,
                shape: IconButtonM3EShapeVariant.round,
              ),
              SizedBox(width: m3e.spacing.sm),
              Text('Manage Groups', style: textTheme.titleLarge),
              const Spacer(),
            ],
          ),
          SizedBox(height: m3e.spacing.lg),
          AppTextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search or select groups',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableGroupsSection(
    BuildContext context,
    _GroupSelectionData data,
  ) {
    final filteredGroups = _filterGroups(data.allGroups);
    final content = _buildGroupsContent(
      filteredGroups: filteredGroups,
      selectedIds: data.selectedIds,
      hasAnyGroups: data.allGroups.isNotEmpty,
      isLoading: data.isLoading,
      isSearching: _searchQuery.isNotEmpty,
      context: context,
    );

    return Column(children: [Expanded(child: content)]);
  }

  Widget _buildGroupsContent({
    required BuildContext context,
    required List<LimitedUserGroups> filteredGroups,
    required Set<String> selectedIds,
    required bool hasAnyGroups,
    required bool isLoading,
    required bool isSearching,
  }) {
    if (isLoading) {
      return const GroupsLoadingState();
    }

    if (filteredGroups.isEmpty) {
      return GroupsEmptyState(
        hasAnyGroups: hasAnyGroups,
        isSearching: isSearching,
        searchQuery: _searchQuery,
      );
    }

    return _buildAvailableGroupsList(context, filteredGroups, selectedIds);
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
    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: context.m3e.spacing.xl),
      itemCount: groups.length,
      separatorBuilder: (_, _) => SizedBox(height: context.m3e.spacing.sm),
      itemBuilder: (context, index) {
        final group = groups[index];
        final isSelected = selectedIds.contains(group.groupId);
        return _buildGroupListItem(context, group, isSelected);
      },
    );
  }

  Widget _buildGroupListItem(
    BuildContext context,
    LimitedUserGroups group,
    bool isSelected,
  ) {
    final m3e = context.m3e;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final memberCount = group.memberCount ?? 0;

    final titleStyle = textTheme.titleMedium?.copyWith(
      color: isSelected ? scheme.onPrimaryContainer : scheme.onSurface,
    );
    final subtitleStyle = textTheme.bodySmall?.copyWith(
      color: isSelected
          ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
          : scheme.onSurfaceVariant,
    );

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: m3e.shapes.square.lg),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => _toggleGroupSelection(group.groupId),
        selected: isSelected,
        leading: GroupAvatar(group: group),
        title: Text(
          group.name ?? 'Unknown Group',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('$memberCount members'),
        titleTextStyle: titleStyle,
        subtitleTextStyle: subtitleStyle,
        contentPadding: EdgeInsets.symmetric(
          horizontal: m3e.spacing.md,
          vertical: m3e.spacing.xs,
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: scheme.onPrimaryContainer,
                size: 24,
              )
            : null,
        tileColor: Colors.transparent,
        selectedTileColor: scheme.primaryContainer,
        iconColor: scheme.onSurfaceVariant,
      ),
    );
  }

  void _toggleGroupSelection(String? groupId) {
    if (groupId == null) {
      return;
    }

    ref
        .read(groupMonitorProvider(widget.userId).notifier)
        .toggleGroupSelection(groupId);
  }
}

class _GroupSelectionData {
  const _GroupSelectionData({
    required this.allGroups,
    required this.selectedIds,
    required this.isLoading,
  });

  final List<LimitedUserGroups> allGroups;
  final Set<String> selectedIds;
  final bool isLoading;
}
