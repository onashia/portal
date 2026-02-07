import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_calendar_event.dart';
import '../providers/api_call_counter.dart';
import '../providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../utils/app_logger.dart';
import '../utils/calendar_event_utils.dart';

@immutable
class GroupCalendarState {
  static const _unset = Object();

  final Map<String, List<CalendarEvent>> eventsByGroup;
  final List<GroupCalendarEvent> todayEvents;
  final Map<String, String> groupErrors;
  final bool isLoading;
  final DateTime? lastFetchedAt;

  const GroupCalendarState({
    this.eventsByGroup = const {},
    this.todayEvents = const [],
    this.groupErrors = const {},
    this.isLoading = false,
    this.lastFetchedAt,
  });

  GroupCalendarState copyWith({
    Map<String, List<CalendarEvent>>? eventsByGroup,
    List<GroupCalendarEvent>? todayEvents,
    Map<String, String>? groupErrors,
    bool? isLoading,
    Object? lastFetchedAt = _unset,
  }) {
    return GroupCalendarState(
      eventsByGroup: eventsByGroup ?? this.eventsByGroup,
      todayEvents: todayEvents ?? this.todayEvents,
      groupErrors: groupErrors ?? this.groupErrors,
      isLoading: isLoading ?? this.isLoading,
      lastFetchedAt: lastFetchedAt == _unset
          ? this.lastFetchedAt
          : lastFetchedAt as DateTime?,
    );
  }
}

class GroupCalendarNotifier extends Notifier<GroupCalendarState> {
  static const _refreshMinutes = 30;
  static const _eventsPerGroup = 60;

  final String userId;

  GroupCalendarNotifier(this.userId);

  Timer? _refreshTimer;
  bool _isFetching = false;

  @override
  GroupCalendarState build() {
    _listenForSelectionChanges();
    _scheduleAutoRefresh();
    ref.onDispose(_disposeTimer);

    Future.microtask(refresh);
    return const GroupCalendarState(isLoading: true);
  }

  void _listenForSelectionChanges() {
    ref.listen<GroupMonitorState>(groupMonitorProvider(userId), (
      previous,
      next,
    ) {
      if (previous == null) {
        return;
      }

      if (!setEquals(previous.selectedGroupIds, next.selectedGroupIds)) {
        unawaited(refresh());
      }
    });
  }

  void _scheduleAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: _refreshMinutes),
      (_) => unawaited(refresh()),
    );
  }

  void _disposeTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> refresh() async {
    if (_isFetching) {
      AppLogger.debug(
        'Calendar refresh already in progress',
        subCategory: 'calendar',
      );
      return;
    }

    final monitorState = ref.read(groupMonitorProvider(userId));
    final selectedGroupIds = monitorState.selectedGroupIds;

    if (selectedGroupIds.isEmpty) {
      state = state.copyWith(
        eventsByGroup: const {},
        todayEvents: const [],
        groupErrors: const {},
        isLoading: false,
        lastFetchedAt: DateTime.now(),
      );
      return;
    }

    _isFetching = true;
    state = state.copyWith(isLoading: true);

    try {
      await _ensureGroupDetails(monitorState);
      final refreshedMonitor = ref.read(groupMonitorProvider(userId));
      final groupLookup = _buildGroupLookup(refreshedMonitor.allGroups);
      final api = ref.read(vrchatApiProvider);

      final updatedEventsByGroup = <String, List<CalendarEvent>>{};
      final updatedErrors = <String, String>{};

      for (final groupId in selectedGroupIds) {
        ref.read(apiCallCounterProvider.notifier).incrementApiCall();
        try {
          final response = await api.rawApi
              .getCalendarApi()
              .getGroupCalendarEvents(groupId: groupId, n: _eventsPerGroup);
          updatedEventsByGroup[groupId] = response.data?.results ?? [];
        } catch (e, s) {
          AppLogger.error(
            'Failed to fetch calendar events for group $groupId',
            subCategory: 'calendar',
            error: e,
            stackTrace: s,
          );
          updatedErrors[groupId] = 'Failed to fetch events';
          final previous = state.eventsByGroup[groupId];
          if (previous != null) {
            updatedEventsByGroup[groupId] = previous;
          }
        }
      }

      final today = DateTime.now();
      final todayEvents = _buildTodayEvents(
        eventsByGroup: updatedEventsByGroup,
        groupLookup: groupLookup,
        today: today,
      );

      state = state.copyWith(
        eventsByGroup: updatedEventsByGroup,
        todayEvents: todayEvents,
        groupErrors: updatedErrors,
        isLoading: false,
        lastFetchedAt: DateTime.now(),
      );
    } catch (e, s) {
      AppLogger.error(
        'Failed to refresh calendar events',
        subCategory: 'calendar',
        error: e,
        stackTrace: s,
      );
      state = state.copyWith(isLoading: false);
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _ensureGroupDetails(GroupMonitorState monitorState) async {
    final selectedGroupIds = monitorState.selectedGroupIds;
    if (selectedGroupIds.isEmpty) {
      return;
    }

    final hasAllGroups =
        monitorState.allGroups.isNotEmpty &&
        selectedGroupIds.every(
          (id) => monitorState.allGroups.any((g) => g.groupId == id),
        );

    if (!hasAllGroups) {
      await ref
          .read(groupMonitorProvider(userId).notifier)
          .fetchUserGroupsIfNeeded();
    }
  }

  Map<String, LimitedUserGroups> _buildGroupLookup(
    List<LimitedUserGroups> groups,
  ) {
    final lookup = <String, LimitedUserGroups>{};
    for (final group in groups) {
      final id = group.groupId;
      if (id != null && id.isNotEmpty) {
        lookup[id] = group;
      }
    }
    return lookup;
  }

  List<GroupCalendarEvent> _buildTodayEvents({
    required Map<String, List<CalendarEvent>> eventsByGroup,
    required Map<String, LimitedUserGroups> groupLookup,
    required DateTime today,
  }) {
    final todayEvents = <GroupCalendarEvent>[];

    for (final entry in eventsByGroup.entries) {
      final groupId = entry.key;
      final group = groupLookup[groupId];

      for (final event in entry.value) {
        if (_shouldSkipEvent(event)) {
          continue;
        }

        if (!overlapsLocalDay(
          start: event.startsAt,
          end: event.endsAt,
          day: today,
        )) {
          continue;
        }

        todayEvents.add(
          GroupCalendarEvent(event: event, groupId: groupId, group: group),
        );
      }
    }

    todayEvents.sort((a, b) => a.event.startsAt.compareTo(b.event.startsAt));
    return todayEvents;
  }

  bool _shouldSkipEvent(CalendarEvent event) {
    if (event.isDraft == true) {
      return true;
    }

    if (event.deletedAt != null) {
      return true;
    }

    return false;
  }
}

final groupCalendarProvider =
    NotifierProvider.family<GroupCalendarNotifier, GroupCalendarState, String>(
      (userId) => GroupCalendarNotifier(userId),
    );
