import 'dart:async';

import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_calendar_event.dart';
import '../providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../providers/portal_api_request_runner_provider.dart';
import '../providers/portal_vrchat_api.dart';
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

  final _calendarLoop = RefreshLoopController();
  final _selectionRefreshDebouncer = RefreshDebouncer();
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
    _selectionRefreshDebouncer.cancel();
    _requestCalendarRefresh(immediate: immediate, bypassRateLimit: true);
  }

  @override
  GroupCalendarState build() {
    _listenForSelectionChanges();
    _listenForAuthChanges();
    ref.onDispose(() {
      _calendarLoop.reset();
      _selectionRefreshDebouncer.cancel();
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
    _calendarLoop.reset();
    _selectionRefreshDebouncer.cancel();
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
    _selectionRefreshDebouncer.schedule(
      delay: AppConstants.selectionRefreshDebounceDuration,
      isMounted: () => ref.mounted,
      onFire: () {
        _requestCalendarRefresh(immediate: true);
      },
    );
  }

  void _requestCalendarRefresh({
    bool immediate = true,
    bool bypassRateLimit = false,
  }) {
    _calendarLoop.requestRefresh(
      isActive: _calendarActive(),
      isInFlight: _isFetching,
      immediate: immediate,
      bypassRateLimit: bypassRateLimit,
      reconcile: _reconcileCalendarLoop,
      runNow: ({required bypassRateLimit}) {
        unawaited(refresh(bypassRateLimit: bypassRateLimit));
      },
      scheduleNextTick: () => _scheduleNextCalendarTick(),
    );
  }

  void _scheduleNextCalendarTick({Duration? overrideDelay}) {
    _calendarLoop.scheduleNextTick(
      isActive: _calendarActive,
      reconcile: _reconcileCalendarLoop,
      resolveDelay: () => const Duration(minutes: _refreshMinutes),
      requestRefresh: () => _requestCalendarRefresh(immediate: true),
      isMounted: () => ref.mounted,
      overrideDelay: overrideDelay,
    );
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

  /// Restores loop invariants after any state change (auth, selection, etc.).
  ///
  /// Checks the current session and selection, then ensures a timer is running
  /// if one is needed. Does not trigger an immediate fetch — call
  /// [_requestCalendarRefresh] for that.
  void _reconcileCalendarLoop() {
    reconcileSingleLoopRefresh(
      loop: _calendarLoop,
      isActive: _calendarActive(),
      isInFlight: _isFetching,
      requestRefresh: () => _requestCalendarRefresh(immediate: true),
      onInactive: () {
        if (!_canRefreshForCurrentSession()) {
          _handleSessionIneligible();
          return;
        }

        _calendarLoop.reset();
        _selectionRefreshDebouncer.cancel();
        _clearForEmptySelectionIfNeeded();
      },
    );
  }

  /// Called in the `finally` block after every fetch completes.
  ///
  /// If a refresh was queued while the previous fetch was in-flight, run it
  /// now. Otherwise schedule the next periodic tick (or reconcile if the loop
  /// is no longer active).
  void _drainPendingRefreshesOrScheduleTick({Duration? overrideDelay}) {
    if (!ref.mounted || _isFetching) {
      return;
    }

    final active = ref.mounted ? _calendarActive() : false;
    drainSingleLoopRefreshOrScheduleNext(
      loop: _calendarLoop,
      isMounted: ref.mounted,
      isInFlight: _isFetching,
      isActive: active,
      runNow: ({required bypassRateLimit}) {
        unawaited(refresh(bypassRateLimit: bypassRateLimit));
      },
      scheduleNextTick: () =>
          _scheduleNextCalendarTick(overrideDelay: overrideDelay),
      reconcile: _reconcileCalendarLoop,
    );
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

    final runner = ref.read(portalApiRequestRunnerProvider);
    if (RefreshCooldownHandler.shouldDeferForCooldown(
      cooldownTracker: runner,
      bypassRateLimit: bypassRateLimit,
      lane: ApiRequestLane.calendar,
      logContext: 'calendar',
      fallbackDelay: const Duration(minutes: _refreshMinutes),
      onDefer: (delay) => _scheduleNextCalendarTick(overrideDelay: delay),
    )) {
      return;
    }

    _isFetching = true;
    Duration? cooldownRetryDelay;
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
      final api = ref.read(portalCalendarApiProvider);
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
        previousGroupErrors: state.groupErrors,
        cooldownTracker: runner,
        lane: ApiRequestLane.calendar,
        respectCooldownBetweenChunks: !bypassRateLimit,
        maxConcurrentRequests: _maxConcurrentRequests,
        fetchEvents: (groupId) async {
          return api.getGroupCalendarEvents(
            groupId: groupId,
            n: _eventsPerGroup,
          );
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
      final shouldKeepLoading =
          fetched.interruptedByCooldown &&
          orderedGroupIds.any(
            (groupId) =>
                !updatedEventsByGroup.containsKey(groupId) &&
                !updatedErrors.containsKey(groupId),
          );
      if (fetched.interruptedByCooldown) {
        cooldownRetryDelay = resolveCooldownAwareDelay(
          remainingCooldown: fetched.cooldownRemaining,
          fallbackDelay: const Duration(minutes: _refreshMinutes),
        );
      }

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
        nextIsLoading: shouldKeepLoading,
      );
      if (shouldEmitState) {
        state = state.copyWith(
          eventsByGroup: selectedData.effectiveEventsByGroup,
          todayEvents: selectedData.effectiveTodayEvents,
          groupErrors: selectedData.effectiveGroupErrors,
          isLoading: shouldKeepLoading,
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
      _drainPendingRefreshesOrScheduleTick(overrideDelay: cooldownRetryDelay);
    }
  }

  /// Guarantees group metadata is available before building today's event list.
  ///
  /// Group details (name, icon, etc.) may not yet be loaded if the calendar
  /// refreshes before the group monitor's first poll completes.
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

  /// Returns true for events that should be excluded from display.
  ///
  /// The VRChat API returns draft and soft-deleted events in the same response
  /// as published ones, so we filter them out client-side.
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

/// Sorts calendar events by start time, then end time, then group ID.
///
/// The group ID tiebreaker produces a stable, deterministic order when two
/// groups schedule events at the same time.
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
