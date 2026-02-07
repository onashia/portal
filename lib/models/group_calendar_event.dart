import 'package:vrchat_dart/vrchat_dart.dart';

/// Associates a calendar event with its owning group for display.
class GroupCalendarEvent {
  /// The VRChat calendar event.
  final CalendarEvent event;

  /// The group ID that owns the event.
  final String groupId;

  /// Optional group metadata for display.
  final LimitedUserGroups? group;

  const GroupCalendarEvent({
    required this.event,
    required this.groupId,
    this.group,
  });
}
