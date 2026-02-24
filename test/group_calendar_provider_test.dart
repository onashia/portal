import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/models/group_calendar_event.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/api_rate_limit_provider.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'test_helpers/auth_test_harness.dart';

class _TestGroupMonitorNotifier extends GroupMonitorNotifier {
  _TestGroupMonitorNotifier(this._initialState) : super('usr_test');

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;

  void setData(GroupMonitorState next) {
    state = next;
  }
}

({
  ProviderContainer container,
  TestAuthNotifier authNotifier,
  _TestGroupMonitorNotifier monitorNotifier,
  NotifierProvider<GroupCalendarNotifier, GroupCalendarState> provider,
  GroupCalendarNotifier notifier,
})
createCalendarHarness({
  required AuthState initialAuthState,
  required GroupMonitorState initialMonitorState,
  String userId = 'usr_test',
}) {
  final monitorNotifier = _TestGroupMonitorNotifier(initialMonitorState);
  final authHarness = createAuthHarness(
    initialAuthState: initialAuthState,
    overrides: [
      groupMonitorProvider(userId).overrideWith(() => monitorNotifier),
    ],
  );
  final provider = groupCalendarProvider(userId);
  final notifier = authHarness.container.read(provider.notifier);
  return (
    container: authHarness.container,
    authNotifier: authHarness.authNotifier,
    monitorNotifier: monitorNotifier,
    provider: provider,
    notifier: notifier,
  );
}

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

  group('calendar state equivalence helpers', () {
    test('calendar event list comparison is deep and value-based', () {
      final previous = _buildEvent(
        id: 'event_1',
        tags: ['tag_a'],
        languages: ['en'],
        roleIds: ['role_1'],
        platforms: [CalendarEventPlatform.standalonewindows],
      );
      final next = _buildEvent(
        id: 'event_1',
        tags: ['tag_a'],
        languages: ['en'],
        roleIds: ['role_1'],
        platforms: [CalendarEventPlatform.standalonewindows],
      );

      expect(areCalendarEventListsEquivalent([previous], [next]), isTrue);
      expect(areCalendarEventsEquivalent(previous, next), isTrue);
    });

    test('calendar event list comparison detects meaningful changes', () {
      final previous = _buildEvent(id: 'event_1', title: 'Title A');
      final next = _buildEvent(id: 'event_1', title: 'Title B');

      expect(areCalendarEventListsEquivalent([previous], [next]), isFalse);
    });

    test('events-by-group comparison ignores map and list identity', () {
      final firstMap = <String, List<CalendarEvent>>{
        'grp_alpha': [_buildEvent(id: 'event_a')],
        'grp_beta': [_buildEvent(id: 'event_b')],
      };
      final secondMap = <String, List<CalendarEvent>>{
        'grp_alpha': [_buildEvent(id: 'event_a')],
        'grp_beta': [_buildEvent(id: 'event_b')],
      };

      expect(areEventsByGroupEquivalent(firstMap, secondMap), isTrue);
    });

    test('today-events comparison is value-based', () {
      final first = [
        GroupCalendarEvent(
          event: _buildEvent(id: 'event_a'),
          groupId: 'grp_alpha',
          group: _buildGroup('grp_alpha', name: 'Alpha'),
        ),
      ];
      final second = [
        GroupCalendarEvent(
          event: _buildEvent(id: 'event_a'),
          groupId: 'grp_alpha',
          group: _buildGroup('grp_alpha', name: 'Alpha'),
        ),
      ];

      expect(areTodayEventsEquivalent(first, second), isTrue);
    });

    test(
      'selectCalendarDataForState reuses previous references when unchanged',
      () {
        final previousEventsByGroup = <String, List<CalendarEvent>>{
          'grp_alpha': [_buildEvent(id: 'event_a')],
        };
        final previousTodayEvents = [
          GroupCalendarEvent(
            event: _buildEvent(id: 'event_a'),
            groupId: 'grp_alpha',
            group: _buildGroup('grp_alpha', name: 'Alpha'),
          ),
        ];
        final previousState = GroupCalendarState(
          eventsByGroup: previousEventsByGroup,
          todayEvents: previousTodayEvents,
          groupErrors: const {'grp_alpha': 'Failed to fetch events'},
          isLoading: false,
          lastDataChangedAt: DateTime.utc(2026, 2, 13, 12, 0),
        );

        final selected = selectCalendarDataForState(
          previousState: previousState,
          nextEventsByGroup: <String, List<CalendarEvent>>{
            'grp_alpha': [_buildEvent(id: 'event_a')],
          },
          nextTodayEvents: [
            GroupCalendarEvent(
              event: _buildEvent(id: 'event_a'),
              groupId: 'grp_alpha',
              group: _buildGroup('grp_alpha', name: 'Alpha'),
            ),
          ],
          nextGroupErrors: const {'grp_alpha': 'Failed to fetch events'},
        );

        expect(selected.didDataChange, isFalse);
        expect(
          identical(
            selected.effectiveEventsByGroup,
            previousState.eventsByGroup,
          ),
          isTrue,
        );
        expect(
          identical(selected.effectiveTodayEvents, previousState.todayEvents),
          isTrue,
        );
        expect(
          identical(selected.effectiveGroupErrors, previousState.groupErrors),
          isTrue,
        );
      },
    );

    test('foreground/background loading write decisions are correct', () {
      const emptyState = GroupCalendarState();
      final populatedState = GroupCalendarState(
        eventsByGroup: <String, List<CalendarEvent>>{
          'grp_alpha': [_buildEvent(id: 'event_a')],
        },
      );

      expect(shouldEnterForegroundCalendarLoading(emptyState), isTrue);
      expect(shouldEnterForegroundCalendarLoading(populatedState), isFalse);
      expect(
        shouldEmitCalendarRefreshStateUpdate(
          currentState: populatedState,
          didDataChange: false,
        ),
        isFalse,
      );
      expect(
        shouldEmitCalendarRefreshStateUpdate(
          currentState: const GroupCalendarState(isLoading: true),
          didDataChange: false,
        ),
        isTrue,
      );
    });
  });

  group('session guards', () {
    test(
      'does not keep a timer when session is eligible but no groups selected',
      () {
        final harness = createCalendarHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          initialMonitorState: const GroupMonitorState(
            selectedGroupIds: <String>{},
          ),
        );
        final notifier = harness.notifier;
        final container = harness.container;
        addTearDown(container.dispose);

        expect(notifier.hasActiveRefreshTimer, isFalse);
      },
    );

    test('refresh does not issue API calls when unauthenticated', () async {
      final harness = createCalendarHarness(
        initialAuthState: unauthenticatedAuthState(),
        initialMonitorState: const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
        ),
      );
      final notifier = harness.notifier;
      final container = harness.container;
      addTearDown(container.dispose);

      await notifier.refresh();

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
    });

    test(
      'refresh does not issue API calls when authenticated user id mismatches',
      () async {
        final harness = createCalendarHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_other'),
          initialMonitorState: const GroupMonitorState(
            selectedGroupIds: {'grp_alpha'},
          ),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        final provider = harness.provider;
        addTearDown(container.dispose);
        final subscription = container.listen<GroupCalendarState>(
          provider,
          (_, next) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        await notifier.refresh();

        expect(container.read(apiCallCounterProvider).totalCalls, 0);
      },
    );

    test('automatic refresh is deferred during calendar cooldown', () async {
      final harness = createCalendarHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        initialMonitorState: const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
        ),
      );
      final container = harness.container;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.calendar,
            retryAfter: const Duration(seconds: 60),
          );

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
      expect(
        container.read(apiCallCounterProvider).throttledSkips,
        greaterThan(0),
      );
    });

    test('manual refresh bypasses calendar cooldown', () async {
      final harness = createCalendarHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        initialMonitorState: const GroupMonitorState(
          selectedGroupIds: {'grp_alpha'},
        ),
      );
      final container = harness.container;
      final notifier = harness.notifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.calendar,
            retryAfter: const Duration(seconds: 60),
          );

      await notifier.refresh(bypassRateLimit: true);

      expect(container.read(apiCallCounterProvider).totalCalls, greaterThan(0));
    });

    test('selection refresh debounce collapses rapid bursts', () async {
      final harness = createCalendarHarness(
        initialAuthState: authenticatedAuthState(userId: 'usr_test'),
        initialMonitorState: const GroupMonitorState(
          selectedGroupIds: <String>{},
        ),
      );
      final container = harness.container;
      final monitorNotifier = harness.monitorNotifier;
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.calendar,
            retryAfter: const Duration(seconds: 60),
          );

      monitorNotifier.setData(
        const GroupMonitorState(selectedGroupIds: {'grp_alpha'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      monitorNotifier.setData(
        const GroupMonitorState(selectedGroupIds: {'grp_alpha', 'grp_beta'}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(container.read(apiCallCounterProvider).throttledSkips, 0);

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(container.read(apiCallCounterProvider).throttledSkips, 1);
    });

    test(
      'refresh timer is cancelled when auth becomes unauthenticated',
      () async {
        final harness = createCalendarHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          initialMonitorState: const GroupMonitorState(
            selectedGroupIds: {'grp_alpha'},
          ),
        );
        final authNotifier = harness.authNotifier;
        final container = harness.container;
        final notifier = harness.notifier;
        final provider = harness.provider;
        addTearDown(container.dispose);
        await Future<void>.delayed(Duration.zero);
        notifier.requestRefresh(immediate: false);

        authNotifier.setData(unauthenticatedAuthState());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final latestNotifier = container.read(provider.notifier);
        expect(latestNotifier.hasActiveRefreshTimer, isFalse);
      },
    );

    test(
      'repeated empty-selection refreshes are a no-op after first clear',
      () async {
        final harness = createCalendarHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          initialMonitorState: const GroupMonitorState(
            selectedGroupIds: <String>{},
          ),
        );
        final container = harness.container;
        final provider = harness.provider;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        await notifier.refresh();
        final afterFirst = container.read(provider);

        await notifier.refresh();
        final afterSecond = container.read(provider);

        expect(identical(afterFirst, afterSecond), isTrue);
        expect(afterSecond.lastDataChangedAt, isNull);
      },
    );

    test(
      'manual refresh queued during in-flight fetch preserves bypass intent',
      () async {
        final harness = createCalendarHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          initialMonitorState: const GroupMonitorState(
            selectedGroupIds: {'grp_alpha'},
          ),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        container
            .read(apiRateLimitCoordinatorProvider)
            .recordRateLimited(
              ApiRequestLane.calendar,
              retryAfter: const Duration(seconds: 60),
            );

        final fetchFuture = notifier.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        notifier.requestRefresh(immediate: true);
        await fetchFuture;

        expect(
          container.read(apiCallCounterProvider).totalCalls,
          greaterThan(0),
        );
      },
    );

    test(
      'direct refresh call during in-flight fetch preserves bypass intent',
      () async {
        final harness = createCalendarHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          initialMonitorState: const GroupMonitorState(
            selectedGroupIds: {'grp_alpha'},
          ),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        container
            .read(apiRateLimitCoordinatorProvider)
            .recordRateLimited(
              ApiRequestLane.calendar,
              retryAfter: const Duration(seconds: 60),
            );

        final fetchFuture = notifier.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        notifier.refresh(bypassRateLimit: true);
        await fetchFuture;

        expect(
          container.read(apiCallCounterProvider).totalCalls,
          greaterThan(0),
        );
      },
    );

    test(
      'multiple queued refreshes accumulate bypass flag correctly',
      () async {
        final harness = createCalendarHarness(
          initialAuthState: authenticatedAuthState(userId: 'usr_test'),
          initialMonitorState: const GroupMonitorState(
            selectedGroupIds: {'grp_alpha'},
          ),
        );
        final container = harness.container;
        final notifier = harness.notifier;
        addTearDown(container.dispose);

        container
            .read(apiRateLimitCoordinatorProvider)
            .recordRateLimited(
              ApiRequestLane.calendar,
              retryAfter: const Duration(seconds: 60),
            );

        final fetchFuture = notifier.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        notifier.requestRefresh(immediate: true);
        notifier.refresh(bypassRateLimit: true);
        await fetchFuture;

        expect(
          container.read(apiCallCounterProvider).totalCalls,
          greaterThan(0),
        );
      },
    );
  });
}

CalendarEvent _buildEvent({
  required String id,
  String? title,
  DateTime? startsAt,
  List<String>? tags,
  List<String>? languages,
  List<String>? roleIds,
  List<CalendarEventPlatform>? platforms,
}) {
  final start = startsAt ?? DateTime.utc(2026, 2, 13, 12, 0);
  return CalendarEvent(
    accessType: CalendarEventAccess.group,
    category: CalendarEventCategory.other,
    description: 'Test event',
    endsAt: start.add(const Duration(hours: 1)),
    id: id,
    startsAt: start,
    title: title ?? 'Event $id',
    tags: tags,
    languages: languages,
    roleIds: roleIds,
    platforms: platforms,
  );
}

LimitedUserGroups _buildGroup(String id, {String? name}) {
  return LimitedUserGroups(groupId: id, name: name ?? id, discriminator: id);
}
