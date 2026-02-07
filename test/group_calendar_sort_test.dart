import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/group_calendar_event.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

void main() {
  group('compareGroupCalendarEvents', () {
    test('sorts by start time, then end time, then groupId', () {
      final start = DateTime(2026, 2, 7, 10, 0);
      final earlierStart = DateTime(2026, 2, 7, 9, 0);
      final endEarly = DateTime(2026, 2, 7, 11, 0);
      final endLate = DateTime(2026, 2, 7, 12, 0);

      final list = [
        GroupCalendarEvent(
          event: _buildEvent(id: 'event-c', startsAt: start, endsAt: endLate),
          groupId: 'groupC',
        ),
        GroupCalendarEvent(
          event: _buildEvent(id: 'event-b', startsAt: start, endsAt: endEarly),
          groupId: 'groupB',
        ),
        GroupCalendarEvent(
          event: _buildEvent(id: 'event-a', startsAt: start, endsAt: endEarly),
          groupId: 'groupA',
        ),
        GroupCalendarEvent(
          event: _buildEvent(
            id: 'event-z',
            startsAt: earlierStart,
            endsAt: endEarly,
          ),
          groupId: 'groupZ',
        ),
      ];

      list.sort(compareGroupCalendarEvents);

      expect(list.map((event) => event.groupId).toList(), [
        'groupZ',
        'groupA',
        'groupB',
        'groupC',
      ]);
    });
  });
}

CalendarEvent _buildEvent({
  required String id,
  required DateTime startsAt,
  required DateTime endsAt,
}) {
  return CalendarEvent(
    accessType: CalendarEventAccess.group,
    category: CalendarEventCategory.other,
    description: 'Test event',
    endsAt: endsAt,
    id: id,
    startsAt: startsAt,
    title: 'Event $id',
  );
}
