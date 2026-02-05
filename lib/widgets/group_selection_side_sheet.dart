import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/group_monitor_provider.dart';
import '../utils/group_utils.dart';
import '../utils/vrchat_image_utils.dart';

class GroupSelectionSideSheet extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onClose;

  const GroupSelectionSideSheet({
    super.key,
    required this.userId,
    required this.onClose,
  });

  @override
  ConsumerState<GroupSelectionSideSheet> createState() =>
      _GroupSelectionSideSheetState();
}

class _GroupSelectionSideSheetState
    extends ConsumerState<GroupSelectionSideSheet> {
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
    return _buildSheetBody(context);
  }

  Widget _buildSheetBody(BuildContext context) {
    final cardTheme = Theme.of(context).cardTheme;
    return Card(
      margin: EdgeInsets.zero,
      color: cardTheme.color,
      elevation: cardTheme.elevation,
      shadowColor: cardTheme.shadowColor,
      surfaceTintColor: cardTheme.surfaceTintColor,
      shape: cardTheme.shape,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: double.infinity,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _buildHeaderSection(context),
              SizedBox(height: context.m3e.spacing.md),
              Expanded(child: _buildAvailableGroupsSection(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: context.m3e.spacing.xl,
        right: context.m3e.spacing.xl,
        top: context.m3e.spacing.lg,
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
              SizedBox(width: context.m3e.spacing.sm),
              Text('Manage Groups', style: textTheme.titleLarge),
              const Spacer(),
            ],
          ),
          SizedBox(height: context.m3e.spacing.lg),
          _buildSearchBar(context),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search or select groups',
        prefixIcon: const Icon(Icons.search),
      ),
    );
  }

  Widget _buildAvailableGroupsSection(BuildContext context) {
    final monitorState = ref.watch(groupMonitorProvider(widget.userId));
    final filteredGroups = _filterGroups(monitorState.allGroups);
    final selectedIds = monitorState.selectedGroupIds;
    final hasAnyGroups = monitorState.allGroups.isNotEmpty;
    final isSearching = _searchQuery.isNotEmpty;

    final content = monitorState.isLoading
        ? _buildLoadingAvailableState(context)
        : filteredGroups.isEmpty
        ? _buildEmptyAvailableState(context, hasAnyGroups, isSearching)
        : _buildAvailableGroupsList(context, filteredGroups, selectedIds);

    return Column(children: [Expanded(child: content)]);
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
      shape: RoundedRectangleBorder(borderRadius: context.m3e.shapes.square.lg),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () {
          if (group.groupId != null) {
            ref
                .read(groupMonitorProvider(widget.userId).notifier)
                .toggleGroupSelection(group.groupId!);
          }
        },
        selected: isSelected,
        leading: _buildGroupAvatar(context, group),
        title: Text(
          group.name ?? 'Unknown Group',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('$memberCount members'),
        titleTextStyle: titleStyle,
        subtitleTextStyle: subtitleStyle,
        contentPadding: EdgeInsets.symmetric(
          horizontal: context.m3e.spacing.md,
          vertical: context.m3e.spacing.xs,
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

  Widget _buildGroupAvatar(BuildContext context, LimitedUserGroups group) {
    final hasImage = group.iconUrl != null && group.iconUrl!.isNotEmpty;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: context.m3e.shapes.square.md,
        color: hasImage ? null : GroupUtils.getAvatarColor(group),
      ),
      child: ClipRRect(
        borderRadius: context.m3e.shapes.square.md,
        clipBehavior: Clip.antiAlias,
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

  Widget _buildEmptyAvailableState(
    BuildContext context,
    bool hasAnyGroups,
    bool isSearching,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final showSecondaryLine = !hasAnyGroups && !isSearching;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.m3e.spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_off, size: 64, color: scheme.onSurfaceVariant),
            SizedBox(height: context.m3e.spacing.lg),
            Text(
              isSearching
                  ? 'No groups match "$_searchQuery"'
                  : 'No groups found',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (showSecondaryLine) ...[
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                'You are not a member of any groups',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
