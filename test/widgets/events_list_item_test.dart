import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:portal/models/group_calendar_event.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/events/events_list_item.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

void main() {
  testWidgets('renders event start time in user local timezone', (
    tester,
  ) async {
    final startsAtUtc = DateTime.utc(2026, 2, 13, 14, 30);
    final event = GroupCalendarEvent(
      event: _buildEvent(
        id: 'event_1',
        title: 'Friday Night Hangout',
        startsAt: startsAtUtc,
        endsAt: startsAtUtc.add(const Duration(hours: 2)),
      ),
      groupId: 'grp_alpha',
      group: LimitedUserGroups(groupId: 'grp_alpha', name: 'Alpha'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 700,
            child: EventsListItem(event: event, isFirst: true, isLast: true),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final expected = DateFormat.jm().format(startsAtUtc.toLocal());
    expect(find.text(expected), findsOneWidget);
  });
}

CalendarEvent _buildEvent({
  required String id,
  required String title,
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
    title: title,
  );
}
