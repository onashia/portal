import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import '../providers/group_monitor_provider.dart';
import '../utils/group_utils.dart';
import '../utils/vrchat_image_utils.dart';
import '../utils/app_logger.dart';

class GroupSelectionPage extends ConsumerStatefulWidget {
  final String userId;
  final OverlayPortalController controller;

  const GroupSelectionPage({
    super.key,
    required this.userId,
    required this.controller,
  });

  @override
  ConsumerState<GroupSelectionPage> createState() => _GroupSelectionPageState();
}

class _GroupSelectionPageState extends ConsumerState<GroupSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.debug(
        'Fetching user groups',
        subCategory: 'group_selection',
      );
      ref.read(groupMonitorProvider(widget.userId).notifier).fetchUserGroups();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LimitedUserGroups> get _filteredGroups {
    final monitorState = ref.read(groupMonitorProvider(widget.userId));
    return monitorState.allGroups.where((group) {
      final name = (group.name ?? '').toLowerCase();
      final discriminator = (group.discriminator ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          discriminator.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final monitorState = ref.watch(groupMonitorProvider(widget.userId));

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: 0.2)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 600,
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(context, monitorState),
                      const Divider(height: 1),
                      _buildSearchBar(context),
                      Expanded(
                        child: monitorState.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _filteredGroups.isEmpty
                            ? _buildEmptyState(context)
                            : _buildGroupGrid(context),
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

  Widget _buildHeader(BuildContext context, GroupMonitorState monitorState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text('Select Groups', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          if (monitorState.selectedGroupIds.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                final notifier = ref.read(
                  groupMonitorProvider(widget.userId).notifier,
                );
                for (final groupId in monitorState.allGroups.map(
                  (g) => g.groupId!,
                )) {
                  notifier.toggleGroupSelection(groupId);
                }
              },
              icon: const Icon(Icons.deselect),
              label: const Text('Deselect All'),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => widget.controller.hide(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search groups...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group_off,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty
                  ? 'No groups found'
                  : 'No groups match "$_searchQuery"',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You are not a member of any groups',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _filteredGroups.length,
        itemBuilder: (context, index) {
          final group = _filteredGroups[index];
          final isSelected = ref
              .watch(groupMonitorProvider(widget.userId))
              .selectedGroupIds
              .contains(group.groupId);

          return _GroupChip(
            group: group,
            isSelected: isSelected,
            onTap: () {
              ref
                  .read(groupMonitorProvider(widget.userId).notifier)
                  .toggleGroupSelection(group.groupId!);
            },
          );
        },
      ),
    );
  }
}

class _GroupChip extends ConsumerWidget {
  final LimitedUserGroups group;
  final bool isSelected;
  final VoidCallback onTap;

  const _GroupChip({
    required this.group,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilterChip(
      selected: isSelected,
      onSelected: (_) => onTap(),
      avatar: _buildAvatar(context, ref),
      label: _buildLabel(context),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
      side: BorderSide(
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, WidgetRef ref) {
    final hasImage = group.iconUrl != null && group.iconUrl!.isNotEmpty;

    return CircleAvatar(
      radius: 16,
      child: ClipOval(
        child: CachedImage(
          imageUrl: hasImage ? group.iconUrl! : '',
          ref: ref,
          width: 32,
          height: 32,
          fallbackWidget: hasImage
              ? null
              : Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: GroupUtils.getAvatarColor(group),
                  ),
                  child: Center(
                    child: Text(
                      GroupUtils.getInitials(group),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
          showLoadingIndicator: false,
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context) {
    final name = group.name ?? 'Unknown Group';
    final memberCount = group.memberCount ?? 0;

    return Text(
      '$name\n$memberCount members',
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
