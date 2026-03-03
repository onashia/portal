import 'dart:async';

import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_calendar_event.dart';
import '../providers/api_call_counter.dart';
import '../providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../providers/polling_lifecycle.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../utils/app_logger.dart';
import '../utils/calendar_event_utils.dart';
import 'refresh_cooldown_handler.dart';
import 'group_calendar_algorithms.dart';
import 'group_calendar_state.dart';

export 'group_calendar_algorithms.dart';
export 'group_calendar_state.dart';

class GroupCalendarNotifier extends Notifier<GroupCalendarState> {
  static const _refreshMinutes = 30;
  static const _eventsPerGroup = 60;
  static const _maxConcurrentRequests = 4;

  final String userId;

  GroupCalendarNotifier(this.userId);

  final _calendarLoop = RefreshLoopState();
  Timer? _selectionRefreshDebounceTimer;
  bool _isFetching = false;

  @visibleForTesting
  bool get hasActiveRefreshTimer => _calendarLoop.hasTimer;

  bool _canRefreshForCurrentSession() {
    final session = ref.read(authSessionSnapshotProvider);
    return isSessionEligible(
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
    _selectionRefreshDebounceTimer?.cancel();
    _selectionRefreshDebounceTimer = null;
    _requestCalendarRefresh(immediate: immediate, bypassRateLimit: true);
  }

  @override
  GroupCalendarState build() {
    _listenForSelectionChanges();
    _listenForAuthChanges();
    ref.onDispose(() {
      _disposeTimer();
      _selectionRefreshDebounceTimer?.cancel();
      _selectionRefreshDebounceTimer = null;
      _calendarLoop.clearPending();
    });

    final shouldRefresh = _calendarActive();
    if (shouldRefresh) {
      Future.microtask(() => _requestCalendarRefresh(immediate: true));
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

      Future.microtask(() {
        if (!ref.mounted) {
          return;
        }
        _reconcileCalendarLoop();
      });
    });
  }

  void _handleSessionIneligible() {
    _disposeTimer();
    _selectionRefreshDebounceTimer?.cancel();
    _selectionRefreshDebounceTimer = null;
    _calendarLoop.clearPending();
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
          _scheduleSelectionTriggeredRefresh();
          return;
        }

        if (becameInactive(previousActive, nextActive)) {
          Future.microtask(() {
            if (!ref.mounted) {
              return;
            }
            _reconcileCalendarLoop();
          });
          return;
        }

        _reconcileCalendarLoop();
      }
    });
  }

  void _scheduleSelectionTriggeredRefresh() {
    _selectionRefreshDebounceTimer?.cancel();
    _selectionRefreshDebounceTimer = Timer(
      AppConstants.selectionRefreshDebounceDuration,
      () {
        if (!ref.mounted) {
          return;
        }
        _requestCalendarRefresh(immediate: true);
      },
    );
  }

  void _requestCalendarRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    final dispatch = shouldRequestImmediateRefresh(
      isActive: _calendarActive(),
      isInFlight: _isFetching,
      immediate: immediate,
    );
    if (dispatch.shouldReconcile) {
      _reconcileCalendarLoop();
      return;
    }

    _calendarLoop.cancelTimer();

    if (dispatch.shouldQueuePending) {
      _calendarLoop.queuePending(bypassRateLimit: bypassRateLimit);
      return;
    }

    if (dispatch.shouldRunNow) {
      unawaited(refresh(bypassRateLimit: bypassRateLimit));
      return;
    }

    if (dispatch.shouldScheduleTick) {
      _scheduleNextCalendarTick();
    }
  }

  void _scheduleNextCalendarTick({Duration? overrideDelay}) {
    _calendarLoop.cancelTimer();

    if (!_calendarActive()) {
      _reconcileCalendarLoop();
      return;
    }

    final delay = overrideDelay ?? const Duration(minutes: _refreshMinutes);
    _calendarLoop.timer = Timer(delay, () {
      if (!ref.mounted) {
        return;
      }
      _requestCalendarRefresh(immediate: true);
    });
  }

  void _disposeTimer() {
    _calendarLoop.cancelTimer();
  }

  void _clearForEmptySelectionIfNeeded() {
    final isNoopState =
        state.eventsByGroup.isEmpty &&
        state.todayEvents.isEmpty &&
        state.groupErrors.isEmpty &&
        !state.isLoading &&
        state.lastDataChangedAt == null;
    if (isNoopState) {
      return;
    }

    state = state.copyWith(
      eventsByGroup: const {},
      todayEvents: const [],
      groupErrors: const {},
      isLoading: false,
      lastDataChangedAt: null,
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
      _selectionRefreshDebounceTimer?.cancel();
      _selectionRefreshDebounceTimer = null;
      _calendarLoop.clearPending();
      _clearForEmptySelectionIfNeeded();
      return;
    }

    if (shouldScheduleNextTick(
      isActive: true,
      hasTimer: _calendarLoop.hasTimer,
      isInFlight: _isFetching,
      hasPendingRefresh: _calendarLoop.pendingRefresh,
    )) {
      _requestCalendarRefresh(immediate: true);
    }
  }

  void _drainPendingRefreshesOrScheduleTick() {
    final active = ref.mounted ? _calendarActive() : false;
    if (shouldDrainPendingRefresh(
      isMounted: ref.mounted,
      isInFlight: _isFetching,
      hasPendingRefresh: _calendarLoop.pendingRefresh,
      isActive: active,
    )) {
      final pending = _calendarLoop.consumePending();
      if (ref.mounted) {
        unawaited(refresh(bypassRateLimit: pending.bypassRateLimit));
      }
      return;
    }

    if (!ref.mounted || _isFetching) {
      return;
    }

    if (shouldScheduleNextTick(
      isActive: active,
      hasTimer: _calendarLoop.hasTimer,
      isInFlight: _isFetching,
      hasPendingRefresh: _calendarLoop.pendingRefresh,
    )) {
      _scheduleNextCalendarTick();
      return;
    }

    _reconcileCalendarLoop();
  }

  Future<void> refresh({bool bypassRateLimit = false}) async {
    if (!ref.mounted) {
      return;
    }
    if (!_calendarActive()) {
      _reconcileCalendarLoop();
      return;
    }

    if (_isFetching) {
      _calendarLoop.queuePending(bypassRateLimit: bypassRateLimit);
      AppLogger.debug(
        'Calendar refresh already in progress',
        subCategory: 'calendar',
      );
      return;
    }

    _calendarLoop.cancelTimer();

    final monitorState = ref.read(groupMonitorProvider(userId));
    final selectedGroupIds = monitorState.selectedGroupIds;

    if (selectedGroupIds.isEmpty) {
      _clearForEmptySelectionIfNeeded();
      return;
    }

    if (RefreshCooldownHandler.shouldDeferForCooldown(
      ref: ref,
      bypassRateLimit: bypassRateLimit,
      lane: ApiRequestLane.calendar,
      logContext: 'calendar',
      fallbackDelay: const Duration(minutes: _refreshMinutes),
      onDefer: (delay) => _scheduleNextCalendarTick(overrideDelay: delay),
    )) {
      return;
    }

    _isFetching = true;
    final previousState = state;
    final shouldEnterForegroundLoading =
        shouldEnterForegroundCalendarLoading(previousState) &&
        !previousState.isLoading;
    if (shouldEnterForegroundLoading) {
      state = state.copyWith(isLoading: true);
    }

    try {
      await _ensureGroupDetails(monitorState);
      final refreshedMonitor = ref.read(groupMonitorProvider(userId));
      final groupLookup = ref.read(groupMonitorAllGroupsByIdProvider(userId));
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
          ref
              .read(apiCallCounterProvider.notifier)
              .incrementApiCall(lane: ApiRequestLane.calendar);
          final response = await api.rawApi
              .getCalendarApi()
              .getGroupCalendarEvents(
                groupId: groupId,
                n: _eventsPerGroup,
                extra: apiRequestLaneExtra(ApiRequestLane.calendar),
              );
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

      final selectedData = selectCalendarDataForState(
        previousState: previousState,
        nextEventsByGroup: updatedEventsByGroup,
        nextTodayEvents: todayEvents,
        nextGroupErrors: updatedErrors,
      );
      final shouldEmitState = shouldEmitCalendarRefreshStateUpdate(
        currentState: state,
        didDataChange: selectedData.didDataChange,
      );
      if (shouldEmitState) {
        state = state.copyWith(
          eventsByGroup: selectedData.effectiveEventsByGroup,
          todayEvents: selectedData.effectiveTodayEvents,
          groupErrors: selectedData.effectiveGroupErrors,
          isLoading: false,
          lastDataChangedAt: selectedData.didDataChange
              ? DateTime.now()
              : state.lastDataChangedAt,
        );
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to refresh calendar events',
        subCategory: 'calendar',
        error: e,
        stackTrace: s,
      );
      if (ref.mounted && state.isLoading) {
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
