import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_calendar_event.dart';
import '../providers/api_call_counter.dart';
import '../providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../providers/polling_lifecycle.dart';
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

@visibleForTesting
Future<
  ({
    Map<String, List<CalendarEvent>> eventsByGroup,
    Map<String, String> groupErrors,
  })
>
fetchGroupCalendarEventsChunked({
  required List<String> orderedGroupIds,
  required Map<String, List<CalendarEvent>> previousEventsByGroup,
  required Future<List<CalendarEvent>> Function(String groupId) fetchEvents,
  int maxConcurrentRequests = 4,
  void Function(String groupId, Object error, StackTrace stackTrace)?
  onFetchError,
}) async {
  if (maxConcurrentRequests < 1) {
    throw ArgumentError.value(
      maxConcurrentRequests,
      'maxConcurrentRequests',
      'must be at least 1',
    );
  }

  final eventsByGroup = <String, List<CalendarEvent>>{};
  final groupErrors = <String, String>{};

  for (
    int start = 0;
    start < orderedGroupIds.length;
    start += maxConcurrentRequests
  ) {
    final end = math.min(start + maxConcurrentRequests, orderedGroupIds.length);
    final chunk = orderedGroupIds.sublist(start, end);

    final chunkResults = await Future.wait(
      chunk.map((groupId) async {
        try {
          final events = await fetchEvents(groupId);
          return (groupId: groupId, events: events, failed: false);
        } catch (e, s) {
          onFetchError?.call(groupId, e, s);
          final previousEvents = previousEventsByGroup[groupId];
          return (groupId: groupId, events: previousEvents, failed: true);
        }
      }),
    );

    for (final result in chunkResults) {
      if (result.events != null) {
        eventsByGroup[result.groupId] = result.events!;
      }
      if (result.failed) {
        groupErrors[result.groupId] = 'Failed to fetch events';
      }
    }
  }

  return (eventsByGroup: eventsByGroup, groupErrors: groupErrors);
}

class GroupCalendarNotifier extends Notifier<GroupCalendarState> {
  static const _refreshMinutes = 30;
  static const _eventsPerGroup = 60;
  static const _maxConcurrentRequests = 4;

  final String userId;

  GroupCalendarNotifier(this.userId);

  Timer? _refreshTimer;
  bool _isFetching = false;
  bool _pendingRefresh = false;

  @visibleForTesting
  bool get hasActiveRefreshTimer => _refreshTimer != null;

  bool _canRefreshForCurrentSession() {
    final session = ref.read(authSessionSnapshotProvider);
    return canPollForUserSession(
      isAuthenticated: session.isAuthenticated,
      authenticatedUserId: session.userId,
      expectedUserId: userId,
    );
  }

  bool _calendarActiveForSelection(Set<String> selectedGroupIds) {
    return isLoopActive(
      isEnabled: true,
      sessionEligible: _canRefreshForCurrentSession(),
      selectionActive: isSelectionActive(selectedGroupIds),
    );
  }

  bool _calendarActiveForSnapshot(
    AuthSessionSnapshot snapshot,
    Set<String> selectedGroupIds,
  ) {
    final sessionEligible = isSessionEligible(
      isAuthenticated: snapshot.isAuthenticated,
      authenticatedUserId: snapshot.userId,
      expectedUserId: userId,
    );
    return isLoopActive(
      isEnabled: true,
      sessionEligible: sessionEligible,
      selectionActive: isSelectionActive(selectedGroupIds),
    );
  }

  bool _calendarActive() {
    final monitorState = ref.read(groupMonitorProvider(userId));
    return _calendarActiveForSelection(monitorState.selectedGroupIds);
  }

  void requestRefresh({bool immediate = true}) {
    _requestCalendarRefresh(immediate: immediate);
  }

  @override
  GroupCalendarState build() {
    _listenForSelectionChanges();
    _listenForAuthChanges();
    ref.onDispose(() {
      _disposeTimer();
      _pendingRefresh = false;
    });

    final shouldRefresh = _calendarActive();
    if (shouldRefresh) {
      Future.microtask(() => requestRefresh(immediate: true));
    }
    return GroupCalendarState(isLoading: shouldRefresh);
  }

  void _listenForAuthChanges() {
    ref.listen<AuthSessionSnapshot>(authSessionSnapshotProvider, (
      previous,
      next,
    ) {
      final selectedGroupIds = ref.read(
        groupMonitorProvider(userId).select((state) => state.selectedGroupIds),
      );
      final previousActive = previous == null
          ? false
          : _calendarActiveForSnapshot(previous, selectedGroupIds);
      final nextActive = _calendarActiveForSnapshot(next, selectedGroupIds);

      if (becameInactive(previousActive, nextActive)) {
        _handleSessionIneligible();
        return;
      }

      if (becameActive(previousActive, nextActive)) {
        _requestCalendarRefresh(immediate: true);
        return;
      }

      _reconcileCalendarLoop();
    });
  }

  void _handleSessionIneligible() {
    _disposeTimer();
    _pendingRefresh = false;
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
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
        final previousActive = _calendarActiveForSelection(
          previous.selectedGroupIds,
        );
        final nextActive = _calendarActiveForSelection(next.selectedGroupIds);

        if (nextActive) {
          _requestCalendarRefresh(immediate: true);
          return;
        }

        if (becameInactive(previousActive, nextActive)) {
          _reconcileCalendarLoop();
          return;
        }

        _reconcileCalendarLoop();
      }
    });
  }

  void _requestCalendarRefresh({bool immediate = true}) {
    if (!_calendarActive()) {
      _reconcileCalendarLoop();
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;

    final decision = resolveRefreshRequestDecision(isInFlight: _isFetching);
    if (decision.shouldQueuePending) {
      _pendingRefresh = true;
      return;
    }

    if (immediate) {
      unawaited(refresh());
      return;
    }

    _scheduleNextCalendarTick();
  }

  void _scheduleNextCalendarTick() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    if (!_calendarActive()) {
      _reconcileCalendarLoop();
      return;
    }

    _refreshTimer = Timer(const Duration(minutes: _refreshMinutes), () {
      if (!ref.mounted) {
        return;
      }
      _requestCalendarRefresh(immediate: true);
    });
  }

  void _disposeTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _clearForEmptySelectionIfNeeded() {
    final isNoopState =
        state.eventsByGroup.isEmpty &&
        state.todayEvents.isEmpty &&
        state.groupErrors.isEmpty &&
        !state.isLoading &&
        state.lastFetchedAt == null;
    if (isNoopState) {
      return;
    }

    state = state.copyWith(
      eventsByGroup: const {},
      todayEvents: const [],
      groupErrors: const {},
      isLoading: false,
      lastFetchedAt: null,
    );
  }

  void _reconcileCalendarLoop() {
    if (!_canRefreshForCurrentSession()) {
      _handleSessionIneligible();
      return;
    }

    final selectedGroupIds = ref.read(
      groupMonitorProvider(userId).select((state) => state.selectedGroupIds),
    );
    if (!isSelectionActive(selectedGroupIds)) {
      _disposeTimer();
      _pendingRefresh = false;
      _clearForEmptySelectionIfNeeded();
      return;
    }

    if (_refreshTimer == null && !_isFetching && !_pendingRefresh) {
      _requestCalendarRefresh(immediate: true);
    }
  }

  void _drainPendingRefreshesOrScheduleTick() {
    if (!ref.mounted || _isFetching) {
      return;
    }

    if (_pendingRefresh && _calendarActive()) {
      _pendingRefresh = false;
      unawaited(refresh());
      return;
    }

    if (_calendarActive() && _refreshTimer == null) {
      _scheduleNextCalendarTick();
      return;
    }

    _reconcileCalendarLoop();
  }

  Future<void> refresh() async {
    if (!_calendarActive()) {
      _reconcileCalendarLoop();
      return;
    }

    if (_isFetching) {
      _pendingRefresh = true;
      AppLogger.debug(
        'Calendar refresh already in progress',
        subCategory: 'calendar',
      );
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;

    final monitorState = ref.read(groupMonitorProvider(userId));
    final selectedGroupIds = monitorState.selectedGroupIds;

    if (selectedGroupIds.isEmpty) {
      _clearForEmptySelectionIfNeeded();
      return;
    }

    _isFetching = true;
    if (!state.isLoading) {
      state = state.copyWith(isLoading: true);
    }

    try {
      await _ensureGroupDetails(monitorState);
      final refreshedMonitor = ref.read(groupMonitorProvider(userId));
      final groupLookup = _buildGroupLookup(refreshedMonitor.allGroups);
      final api = ref.read(vrchatApiProvider);
      final orderedGroupIds = refreshedMonitor.selectedGroupIds.toList(
        growable: false,
      )..sort();
      if (orderedGroupIds.isEmpty) {
        _clearForEmptySelectionIfNeeded();
        return;
      }
      final fetched = await fetchGroupCalendarEventsChunked(
        orderedGroupIds: orderedGroupIds,
        previousEventsByGroup: state.eventsByGroup,
        maxConcurrentRequests: _maxConcurrentRequests,
        fetchEvents: (groupId) async {
          ref.read(apiCallCounterProvider.notifier).incrementApiCall();
          final response = await api.rawApi
              .getCalendarApi()
              .getGroupCalendarEvents(groupId: groupId, n: _eventsPerGroup);
          return response.data?.results ?? [];
        },
        onFetchError: (groupId, error, stackTrace) {
          AppLogger.error(
            'Failed to fetch calendar events for group $groupId',
            subCategory: 'calendar',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
      final updatedEventsByGroup = fetched.eventsByGroup;
      final updatedErrors = fetched.groupErrors;

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
      if (state.isLoading) {
        state = state.copyWith(isLoading: false);
      }
    } finally {
      _isFetching = false;
      _drainPendingRefreshesOrScheduleTick();
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

    todayEvents.sort(compareGroupCalendarEvents);
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

@visibleForTesting
int compareGroupCalendarEvents(GroupCalendarEvent a, GroupCalendarEvent b) {
  final startCompare = a.event.startsAt.compareTo(b.event.startsAt);
  if (startCompare != 0) {
    return startCompare;
  }

  final endCompare = a.event.endsAt.compareTo(b.event.endsAt);
  if (endCompare != 0) {
    return endCompare;
  }

  return a.groupId.compareTo(b.groupId);
}

final groupCalendarProvider =
    NotifierProvider.family<GroupCalendarNotifier, GroupCalendarState, String>(
      (userId) => GroupCalendarNotifier(userId),
    );
