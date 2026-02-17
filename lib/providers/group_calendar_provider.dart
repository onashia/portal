import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_calendar_event.dart';
import '../providers/api_call_counter.dart';
import '../providers/api_rate_limit_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/group_monitor_provider.dart';
import '../providers/polling_lifecycle.dart';
import '../services/api_rate_limit_coordinator.dart';
import '../utils/app_logger.dart';
import '../utils/calendar_event_utils.dart';

@immutable
class GroupCalendarState {
  static const _unset = Object();

  final Map<String, List<CalendarEvent>> eventsByGroup;
  final List<GroupCalendarEvent> todayEvents;
  final Map<String, String> groupErrors;
  final bool isLoading;
  final DateTime? lastDataChangedAt;

  const GroupCalendarState({
    this.eventsByGroup = const {},
    this.todayEvents = const [],
    this.groupErrors = const {},
    this.isLoading = false,
    this.lastDataChangedAt,
  });

  GroupCalendarState copyWith({
    Map<String, List<CalendarEvent>>? eventsByGroup,
    List<GroupCalendarEvent>? todayEvents,
    Map<String, String>? groupErrors,
    bool? isLoading,
    Object? lastDataChangedAt = _unset,
  }) {
    return GroupCalendarState(
      eventsByGroup: eventsByGroup ?? this.eventsByGroup,
      todayEvents: todayEvents ?? this.todayEvents,
      groupErrors: groupErrors ?? this.groupErrors,
      isLoading: isLoading ?? this.isLoading,
      lastDataChangedAt: lastDataChangedAt == _unset
          ? this.lastDataChangedAt
          : lastDataChangedAt as DateTime?,
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

bool _areListsEquivalent<T>(
  List<T>? previous,
  List<T>? next, {
  bool Function(T previous, T next)? equals,
}) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous == null || next == null) {
    return previous == null && next == null;
  }
  if (previous.length != next.length) {
    return false;
  }

  final itemEquals = equals ?? (T a, T b) => a == b;
  for (int i = 0; i < previous.length; i++) {
    if (!itemEquals(previous[i], next[i])) {
      return false;
    }
  }
  return true;
}

@visibleForTesting
bool areCalendarEventsEquivalent(CalendarEvent previous, CalendarEvent next) {
  return previous.accessType == next.accessType &&
      previous.category == next.category &&
      previous.closeInstanceAfterEndMinutes ==
          next.closeInstanceAfterEndMinutes &&
      previous.createdAt == next.createdAt &&
      previous.deletedAt == next.deletedAt &&
      previous.description == next.description &&
      previous.durationInMs == next.durationInMs &&
      previous.endsAt == next.endsAt &&
      previous.featured == next.featured &&
      previous.guestEarlyJoinMinutes == next.guestEarlyJoinMinutes &&
      previous.hostEarlyJoinMinutes == next.hostEarlyJoinMinutes &&
      previous.id == next.id &&
      previous.imageId == next.imageId &&
      previous.imageUrl == next.imageUrl &&
      previous.interestedUserCount == next.interestedUserCount &&
      previous.isDraft == next.isDraft &&
      _areListsEquivalent(previous.languages, next.languages) &&
      previous.ownerId == next.ownerId &&
      _areListsEquivalent(previous.platforms, next.platforms) &&
      _areListsEquivalent(previous.roleIds, next.roleIds) &&
      previous.startsAt == next.startsAt &&
      _areListsEquivalent(previous.tags, next.tags) &&
      previous.title == next.title &&
      previous.type == next.type &&
      previous.updatedAt == next.updatedAt &&
      previous.userInterest == next.userInterest &&
      previous.usesInstanceOverflow == next.usesInstanceOverflow;
}

@visibleForTesting
bool areCalendarEventListsEquivalent(
  List<CalendarEvent> previous,
  List<CalendarEvent> next,
) {
  return _areListsEquivalent(
    previous,
    next,
    equals: areCalendarEventsEquivalent,
  );
}

@visibleForTesting
bool areEventsByGroupEquivalent(
  Map<String, List<CalendarEvent>> previous,
  Map<String, List<CalendarEvent>> next,
) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous.length != next.length) {
    return false;
  }

  for (final entry in previous.entries) {
    final nextEvents = next[entry.key];
    if (nextEvents == null ||
        !areCalendarEventListsEquivalent(entry.value, nextEvents)) {
      return false;
    }
  }

  return true;
}

@visibleForTesting
bool areStringMapsEquivalent(
  Map<String, String> previous,
  Map<String, String> next,
) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous.length != next.length) {
    return false;
  }

  for (final entry in previous.entries) {
    if (next[entry.key] != entry.value) {
      return false;
    }
  }

  return true;
}

@visibleForTesting
bool areTodayEventsEquivalent(
  List<GroupCalendarEvent> previous,
  List<GroupCalendarEvent> next,
) {
  if (identical(previous, next)) {
    return true;
  }
  if (previous.length != next.length) {
    return false;
  }

  for (int i = 0; i < previous.length; i++) {
    final previousEvent = previous[i];
    final nextEvent = next[i];
    if (previousEvent.groupId != nextEvent.groupId ||
        previousEvent.group != nextEvent.group ||
        !areCalendarEventsEquivalent(previousEvent.event, nextEvent.event)) {
      return false;
    }
  }

  return true;
}

@visibleForTesting
({
  Map<String, List<CalendarEvent>> effectiveEventsByGroup,
  List<GroupCalendarEvent> effectiveTodayEvents,
  Map<String, String> effectiveGroupErrors,
  bool didDataChange,
})
selectCalendarDataForState({
  required GroupCalendarState previousState,
  required Map<String, List<CalendarEvent>> nextEventsByGroup,
  required List<GroupCalendarEvent> nextTodayEvents,
  required Map<String, String> nextGroupErrors,
}) {
  final didEventsByGroupChange = !areEventsByGroupEquivalent(
    previousState.eventsByGroup,
    nextEventsByGroup,
  );
  final didTodayEventsChange = !areTodayEventsEquivalent(
    previousState.todayEvents,
    nextTodayEvents,
  );
  final didGroupErrorsChange = !areStringMapsEquivalent(
    previousState.groupErrors,
    nextGroupErrors,
  );
  final didDataChange =
      didEventsByGroupChange || didTodayEventsChange || didGroupErrorsChange;

  return (
    effectiveEventsByGroup: didEventsByGroupChange
        ? nextEventsByGroup
        : previousState.eventsByGroup,
    effectiveTodayEvents: didTodayEventsChange
        ? nextTodayEvents
        : previousState.todayEvents,
    effectiveGroupErrors: didGroupErrorsChange
        ? nextGroupErrors
        : previousState.groupErrors,
    didDataChange: didDataChange,
  );
}

@visibleForTesting
bool shouldEnterForegroundCalendarLoading(GroupCalendarState currentState) {
  return currentState.eventsByGroup.isEmpty &&
      currentState.todayEvents.isEmpty &&
      currentState.groupErrors.isEmpty;
}

@visibleForTesting
bool shouldEmitCalendarRefreshStateUpdate({
  required GroupCalendarState currentState,
  required bool didDataChange,
}) {
  return didDataChange || currentState.isLoading;
}

class GroupCalendarNotifier extends Notifier<GroupCalendarState> {
  static const _refreshMinutes = 30;
  static const _eventsPerGroup = 60;
  static const _maxConcurrentRequests = 4;

  final String userId;

  GroupCalendarNotifier(this.userId);

  Timer? _refreshTimer;
  Timer? _selectionRefreshDebounceTimer;
  bool _isFetching = false;
  bool _pendingRefresh = false;
  bool _pendingBypassRateLimit = false;

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
      _pendingRefresh = false;
      _pendingBypassRateLimit = false;
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
    _pendingRefresh = false;
    _pendingBypassRateLimit = false;
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
    if (!_calendarActive()) {
      _reconcileCalendarLoop();
      return;
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;

    final decision = resolveRefreshRequestDecision(isInFlight: _isFetching);
    if (decision.shouldQueuePending) {
      _pendingRefresh = true;
      _pendingBypassRateLimit = _pendingBypassRateLimit || bypassRateLimit;
      return;
    }

    if (immediate) {
      unawaited(refresh(bypassRateLimit: bypassRateLimit));
      return;
    }

    _scheduleNextCalendarTick();
  }

  void _scheduleNextCalendarTick({Duration? overrideDelay}) {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    if (!_calendarActive()) {
      _reconcileCalendarLoop();
      return;
    }

    final delay = overrideDelay ?? const Duration(minutes: _refreshMinutes);
    _refreshTimer = Timer(delay, () {
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
      _pendingRefresh = false;
      _pendingBypassRateLimit = false;
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
      final bypassRateLimit = _pendingBypassRateLimit;
      _pendingRefresh = false;
      _pendingBypassRateLimit = false;
      if (ref.mounted) {
        unawaited(refresh(bypassRateLimit: bypassRateLimit));
      }
      return;
    }

    if (_calendarActive() && _refreshTimer == null) {
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
      _pendingRefresh = true;
      _pendingBypassRateLimit = _pendingBypassRateLimit || bypassRateLimit;
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

    if (!bypassRateLimit) {
      final coordinator = ref.read(apiRateLimitCoordinatorProvider);
      final remaining = coordinator.remainingCooldown(ApiRequestLane.calendar);
      if (remaining != null) {
        AppLogger.debug(
          'Calendar refresh deferred due to cooldown'
          ' (${remaining.inSeconds}s remaining)',
          subCategory: 'calendar',
        );
        ref
            .read(apiCallCounterProvider.notifier)
            .incrementThrottledSkip(lane: ApiRequestLane.calendar);
        _scheduleNextCalendarTick(
          overrideDelay: resolveCooldownAwareDelay(
            remainingCooldown: remaining,
            fallbackDelay: const Duration(minutes: _refreshMinutes),
          ),
        );
        return;
      }
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
        if (selectedData.didDataChange) {
          state = state.copyWith(
            eventsByGroup: selectedData.effectiveEventsByGroup,
            todayEvents: selectedData.effectiveTodayEvents,
            groupErrors: selectedData.effectiveGroupErrors,
            isLoading: false,
            lastDataChangedAt: DateTime.now(),
          );
        } else {
          state = state.copyWith(
            eventsByGroup: selectedData.effectiveEventsByGroup,
            todayEvents: selectedData.effectiveTodayEvents,
            groupErrors: selectedData.effectiveGroupErrors,
            isLoading: false,
          );
        }
      }
    } catch (e, s) {
      AppLogger.error(
        'Failed to refresh calendar events',
        subCategory: 'calendar',
        error: e,
        stackTrace: s,
      );
      if (state.isLoading && ref.mounted) {
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
