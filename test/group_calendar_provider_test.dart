import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
        expect(afterSecond.lastFetchedAt, isNull);
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
