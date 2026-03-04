import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_calendar_event.dart';
import '../utils/chunked_async.dart';
import '../utils/collection_equivalence.dart' as collection_eq;
import 'group_calendar_state.dart';

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
  final eventsByGroup = <String, List<CalendarEvent>>{};
  final groupErrors = <String, String>{};

  final results =
      await runInChunks<
        String,
        ({String groupId, List<CalendarEvent>? events, bool failed})
      >(
        items: orderedGroupIds,
        maxConcurrent: maxConcurrentRequests,
        operation: (groupId) async {
          try {
            final events = await fetchEvents(groupId);
            return (groupId: groupId, events: events, failed: false);
          } catch (e, s) {
            onFetchError?.call(groupId, e, s);
            final previousEvents = previousEventsByGroup[groupId];
            return (groupId: groupId, events: previousEvents, failed: true);
          }
        },
      );

  for (final result in results) {
    if (result.events != null) {
      eventsByGroup[result.groupId] = result.events!;
    }
    if (result.failed) {
      groupErrors[result.groupId] = 'Failed to fetch events';
    }
  }

  return (eventsByGroup: eventsByGroup, groupErrors: groupErrors);
}

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
      collection_eq.areListsEquivalent(previous.languages, next.languages) &&
      previous.ownerId == next.ownerId &&
      collection_eq.areListsEquivalent(previous.platforms, next.platforms) &&
      collection_eq.areListsEquivalent(previous.roleIds, next.roleIds) &&
      previous.startsAt == next.startsAt &&
      collection_eq.areListsEquivalent(previous.tags, next.tags) &&
      previous.title == next.title &&
      previous.type == next.type &&
      previous.updatedAt == next.updatedAt &&
      previous.userInterest == next.userInterest &&
      previous.usesInstanceOverflow == next.usesInstanceOverflow;
}

bool areCalendarEventListsEquivalent(
  List<CalendarEvent> previous,
  List<CalendarEvent> next,
) {
  return collection_eq.areListsEquivalent(
    previous,
    next,
    equals: areCalendarEventsEquivalent,
  );
}

bool areEventsByGroupEquivalent(
  Map<String, List<CalendarEvent>> previous,
  Map<String, List<CalendarEvent>> next,
) {
  return collection_eq.areMapsEquivalent(
    previous,
    next,
    valueEquals: areCalendarEventListsEquivalent,
  );
}

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
  final didGroupErrorsChange = !collection_eq.areMapsEquivalent(
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

bool shouldEnterForegroundCalendarLoading(GroupCalendarState currentState) {
  return currentState.eventsByGroup.isEmpty &&
      currentState.todayEvents.isEmpty &&
      currentState.groupErrors.isEmpty;
}

bool shouldEmitCalendarRefreshStateUpdate({
  required GroupCalendarState currentState,
  required bool didDataChange,
}) {
  return didDataChange || currentState.isLoading;
}
