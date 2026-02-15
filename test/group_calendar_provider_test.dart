import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/models/group_calendar_event.dart';
import 'package:portal/providers/api_call_counter.dart';
import 'package:portal/providers/api_rate_limit_provider.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._initialState);

  final AuthState _initialState;

  @override
  AuthState build() => _initialState;

  void setData(AuthState next) {
    state = AsyncData(next);
  }
}

class _TestGroupMonitorNotifier extends GroupMonitorNotifier {
  _TestGroupMonitorNotifier(this._initialState) : super('usr_test');

  final GroupMonitorState _initialState;

  @override
  GroupMonitorState build() => _initialState;

  void setData(GroupMonitorState next) {
    state = next;
  }
}

class _MockCurrentUser extends Mock implements CurrentUser {}

CurrentUser _mockCurrentUser(String id) {
  final user = _MockCurrentUser();
  when(() => user.id).thenReturn(id);
  return user;
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
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              () => _TestAuthNotifier(
                AuthState(
                  status: AuthStatus.authenticated,
                  currentUser: _mockCurrentUser('usr_test'),
                ),
              ),
            ),
            groupMonitorProvider('usr_test').overrideWith(
              () => _TestGroupMonitorNotifier(
                const GroupMonitorState(selectedGroupIds: <String>{}),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          groupCalendarProvider('usr_test').notifier,
        );

        expect(notifier.hasActiveRefreshTimer, isFalse);
      },
    );

    test('refresh does not issue API calls when unauthenticated', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _TestAuthNotifier(
              const AuthState(status: AuthStatus.unauthenticated),
            ),
          ),
          groupMonitorProvider('usr_test').overrideWith(
            () => _TestGroupMonitorNotifier(
              const GroupMonitorState(selectedGroupIds: {'grp_alpha'}),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(
        groupCalendarProvider('usr_test').notifier,
      );
      await notifier.refresh();

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
    });

    test(
      'refresh does not issue API calls when authenticated user id mismatches',
      () async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              () => _TestAuthNotifier(
                AuthState(
                  status: AuthStatus.authenticated,
                  currentUser: _mockCurrentUser('usr_other'),
                ),
              ),
            ),
            groupMonitorProvider('usr_test').overrideWith(
              () => _TestGroupMonitorNotifier(
                const GroupMonitorState(selectedGroupIds: {'grp_alpha'}),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen<GroupCalendarState>(
          groupCalendarProvider('usr_test'),
          (_, next) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);

        final notifier = container.read(
          groupCalendarProvider('usr_test').notifier,
        );
        await notifier.refresh();

        expect(container.read(apiCallCounterProvider).totalCalls, 0);
      },
    );

    test('automatic refresh is deferred during calendar cooldown', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _TestAuthNotifier(
              AuthState(
                status: AuthStatus.authenticated,
                currentUser: _mockCurrentUser('usr_test'),
              ),
            ),
          ),
          groupMonitorProvider('usr_test').overrideWith(
            () => _TestGroupMonitorNotifier(
              const GroupMonitorState(selectedGroupIds: {'grp_alpha'}),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.calendar,
            retryAfter: const Duration(seconds: 60),
          );

      container.read(groupCalendarProvider('usr_test').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(container.read(apiCallCounterProvider).totalCalls, 0);
      expect(
        container.read(apiCallCounterProvider).throttledSkips,
        greaterThan(0),
      );
    });

    test('manual refresh bypasses calendar cooldown', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _TestAuthNotifier(
              AuthState(
                status: AuthStatus.authenticated,
                currentUser: _mockCurrentUser('usr_test'),
              ),
            ),
          ),
          groupMonitorProvider('usr_test').overrideWith(
            () => _TestGroupMonitorNotifier(
              const GroupMonitorState(selectedGroupIds: {'grp_alpha'}),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.calendar,
            retryAfter: const Duration(seconds: 60),
          );

      final notifier = container.read(
        groupCalendarProvider('usr_test').notifier,
      );
      await notifier.refresh(bypassRateLimit: true);

      expect(container.read(apiCallCounterProvider).totalCalls, greaterThan(0));
    });

    test('selection refresh debounce collapses rapid bursts', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => _TestAuthNotifier(
              AuthState(
                status: AuthStatus.authenticated,
                currentUser: _mockCurrentUser('usr_test'),
              ),
            ),
          ),
          groupMonitorProvider('usr_test').overrideWith(
            () => _TestGroupMonitorNotifier(
              const GroupMonitorState(selectedGroupIds: <String>{}),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.calendar,
            retryAfter: const Duration(seconds: 60),
          );

      container.read(groupCalendarProvider('usr_test').notifier);
      final monitorNotifier =
          container.read(groupMonitorProvider('usr_test').notifier)
              as _TestGroupMonitorNotifier;

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
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              () => _TestAuthNotifier(
                AuthState(
                  status: AuthStatus.authenticated,
                  currentUser: _mockCurrentUser('usr_test'),
                ),
              ),
            ),
            groupMonitorProvider('usr_test').overrideWith(
              () => _TestGroupMonitorNotifier(
                const GroupMonitorState(selectedGroupIds: {'grp_alpha'}),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(
          groupCalendarProvider('usr_test').notifier,
        );
        final authNotifier =
            container.read(authProvider.notifier) as _TestAuthNotifier;
        await Future<void>.delayed(Duration.zero);
        notifier.requestRefresh(immediate: false);

        authNotifier.setData(
          const AuthState(status: AuthStatus.unauthenticated),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final latestNotifier = container.read(
          groupCalendarProvider('usr_test').notifier,
        );
        expect(latestNotifier.hasActiveRefreshTimer, isFalse);
      },
    );

    test(
      'repeated empty-selection refreshes are a no-op after first clear',
      () async {
        final container = ProviderContainer(
          overrides: [
            authProvider.overrideWith(
              () => _TestAuthNotifier(
                AuthState(
                  status: AuthStatus.authenticated,
                  currentUser: _mockCurrentUser('usr_test'),
                ),
              ),
            ),
            groupMonitorProvider('usr_test').overrideWith(
              () => _TestGroupMonitorNotifier(
                const GroupMonitorState(selectedGroupIds: <String>{}),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final provider = groupCalendarProvider('usr_test');
        final notifier = container.read(provider.notifier);
        await notifier.refresh();
        final afterFirst = container.read(provider);

        await notifier.refresh();
        final afterSecond = container.read(provider);

        expect(identical(afterFirst, afterSecond), isTrue);
        expect(afterSecond.lastDataChangedAt, isNull);
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
