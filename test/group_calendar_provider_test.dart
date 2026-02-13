import 'package:flutter_test/flutter_test.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

void main() {
  group('fetchGroupCalendarEventsChunked', () {
    test('fetches in deterministic chunks with bounded concurrency', () async {
      final orderedGroupIds = ['grp_a', 'grp_b', 'grp_c', 'grp_d', 'grp_e'];
      var inFlight = 0;
      var maxInFlight = 0;
      final started = <String>[];

      final result = await fetchGroupCalendarEventsChunked(
        orderedGroupIds: orderedGroupIds,
        previousEventsByGroup: const {},
        maxConcurrentRequests: 2,
        fetchEvents: (groupId) async {
          started.add(groupId);
          inFlight += 1;
          if (inFlight > maxInFlight) {
            maxInFlight = inFlight;
          }

          await Future<void>.delayed(const Duration(milliseconds: 10));
          inFlight -= 1;

          return [_buildEvent(id: 'event_$groupId')];
        },
      );

      expect(started, orderedGroupIds);
      expect(maxInFlight, lessThanOrEqualTo(2));
      expect(result.groupErrors, isEmpty);
      expect(result.eventsByGroup.keys.toList(), orderedGroupIds);
    });

    test(
      'preserves previous data on partial failure and records errors',
      () async {
        final orderedGroupIds = ['grp_a', 'grp_b', 'grp_c', 'grp_d'];
        final previousEventsByGroup = {
          'grp_b': [_buildEvent(id: 'previous_grp_b')],
        };
        final fetchErrors = <String>[];

        final result = await fetchGroupCalendarEventsChunked(
          orderedGroupIds: orderedGroupIds,
          previousEventsByGroup: previousEventsByGroup,
          maxConcurrentRequests: 2,
          fetchEvents: (groupId) async {
            if (groupId == 'grp_b' || groupId == 'grp_c') {
              throw StateError('fetch failed');
            }
            return [_buildEvent(id: 'fresh_$groupId')];
          },
          onFetchError: (groupId, error, stackTrace) {
            fetchErrors.add(groupId);
          },
        );

        expect(result.groupErrors, {
          'grp_b': 'Failed to fetch events',
          'grp_c': 'Failed to fetch events',
        });
        expect(fetchErrors, ['grp_b', 'grp_c']);

        expect(result.eventsByGroup['grp_a']?.first.id, 'fresh_grp_a');
        expect(result.eventsByGroup['grp_b']?.first.id, 'previous_grp_b');
        expect(result.eventsByGroup.containsKey('grp_c'), isFalse);
        expect(result.eventsByGroup['grp_d']?.first.id, 'fresh_grp_d');
      },
    );
  });
}

CalendarEvent _buildEvent({required String id}) {
  final start = DateTime.utc(2026, 2, 13, 12, 0);
  return CalendarEvent(
    accessType: CalendarEventAccess.group,
    category: CalendarEventCategory.other,
    description: 'Test event',
    endsAt: start.add(const Duration(hours: 1)),
    id: id,
    startsAt: start,
    title: 'Event $id',
  );
}
