import 'package:flutter/foundation.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../models/group_calendar_event.dart';

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
