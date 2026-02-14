import 'dart:async';

import 'package:dio/dio.dart' as dio;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/providers/api_rate_limit_provider.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/vrchat_status_provider.dart';
import 'package:portal/services/api_rate_limit_coordinator.dart';
import 'package:vrchat_dart/vrchat_dart.dart' show CurrentUser;

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._initialState);

  final AuthState _initialState;

  @override
  AuthState build() => _initialState;

  void setData(AuthState next) {
    state = AsyncData(next);
  }
}

class _MockDio extends Mock implements dio.Dio {}

class _MockCurrentUser extends Mock implements CurrentUser {}

class _NoopErrorInterceptorHandler extends dio.ErrorInterceptorHandler {
  @override
  void next(dio.DioException error) {}

  @override
  void reject(dio.DioException error) {}

  @override
  void resolve(dio.Response<dynamic> response) {}
}

CurrentUser _mockCurrentUser(String id) {
  final user = _MockCurrentUser();
  when(() => user.id).thenReturn(id);
  return user;
}

dio.Response<Map<String, dynamic>> _statusResponse() {
  return dio.Response<Map<String, dynamic>>(
    data: {
      'status': {'indicator': 'none', 'description': 'All systems operational'},
      'components': <Map<String, dynamic>>[],
      'incidents': <Map<String, dynamic>>[],
    },
    statusCode: 200,
    requestOptions: dio.RequestOptions(path: '/summary.json'),
  );
}

void main() {
  test('refresh does not call status API when unauthenticated', () async {
    final mockDio = _MockDio();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _TestAuthNotifier(
            const AuthState(status: AuthStatus.unauthenticated),
          ),
        ),
        dioProvider.overrideWith((ref) => mockDio),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(vrchatStatusProvider.notifier);
    await notifier.refresh();

    verifyNever(() => mockDio.get(any(), options: any(named: 'options')));
  });

  test(
    'automatic refresh is suppressed while status lane is cooling down',
    () async {
      final mockDio = _MockDio();
      when(
        () => mockDio.get(any(), options: any(named: 'options')),
      ).thenAnswer((_) async => _statusResponse());
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
          dioProvider.overrideWith((ref) => mockDio),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(apiRateLimitCoordinatorProvider)
          .recordRateLimited(
            ApiRequestLane.status,
            retryAfter: const Duration(seconds: 60),
          );

      container.read(vrchatStatusProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      verifyNever(() => mockDio.get(any(), options: any(named: 'options')));
    },
  );

  test('manual refresh bypasses status cooldown', () async {
    final mockDio = _MockDio();
    when(
      () => mockDio.get(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => _statusResponse());
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
        dioProvider.overrideWith((ref) => mockDio),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(apiRateLimitCoordinatorProvider)
        .recordRateLimited(
          ApiRequestLane.status,
          retryAfter: const Duration(seconds: 60),
        );

    final notifier = container.read(vrchatStatusProvider.notifier);
    await notifier.refresh(bypassRateLimit: true);

    verify(() => mockDio.get(any(), options: any(named: 'options'))).called(1);
  });

  test('default refresh respects status cooldown', () async {
    final mockDio = _MockDio();
    when(
      () => mockDio.get(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => _statusResponse());
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
        dioProvider.overrideWith((ref) => mockDio),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(apiRateLimitCoordinatorProvider)
        .recordRateLimited(
          ApiRequestLane.status,
          retryAfter: const Duration(seconds: 60),
        );

    final notifier = container.read(vrchatStatusProvider.notifier);
    await notifier.refresh();

    verifyNever(() => mockDio.get(any(), options: any(named: 'options')));
  });

  test('429 response enters cooldown for status lane', () async {
    final coordinator = ApiRateLimitCoordinator();
    final interceptor = ApiRateLimitInterceptor(coordinator);
    final requestOptions = dio.RequestOptions(
      path: '/summary.json',
      extra: apiRequestLaneExtra(ApiRequestLane.status),
    );
    final error = dio.DioException.badResponse(
      statusCode: 429,
      requestOptions: requestOptions,
      response: dio.Response<Map<String, dynamic>>(
        statusCode: 429,
        requestOptions: requestOptions,
        headers: dio.Headers.fromMap({
          'retry-after': <String>['60'],
        }),
      ),
    );

    interceptor.onError(error, _NoopErrorInterceptorHandler());
    expect(coordinator.canRequest(ApiRequestLane.status), isFalse);
    expect(coordinator.remainingCooldown(ApiRequestLane.status), isNotNull);
  });

  test('polling resumes after auth transitions to authenticated', () async {
    final mockDio = _MockDio();
    when(
      () => mockDio.get(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => _statusResponse());
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _TestAuthNotifier(
            const AuthState(status: AuthStatus.unauthenticated),
          ),
        ),
        dioProvider.overrideWith((ref) => mockDio),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen<AsyncValue<VrchatStatusState>>(
      vrchatStatusProvider,
      (_, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final authNotifier =
        container.read(authProvider.notifier) as _TestAuthNotifier;
    container.read(vrchatStatusProvider.notifier);
    authNotifier.setData(
      AuthState(
        status: AuthStatus.authenticated,
        currentUser: _mockCurrentUser('usr_test'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    verify(() => mockDio.get(any(), options: any(named: 'options'))).called(1);
  });

  test(
    'in-flight success completion after logout does not overwrite unauthenticated safe state',
    () async {
      final mockDio = _MockDio();
      final responseCompleter = Completer<dio.Response<Map<String, dynamic>>>();
      when(
        () => mockDio.get(any(), options: any(named: 'options')),
      ).thenAnswer((_) => responseCompleter.future);
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
          dioProvider.overrideWith((ref) => mockDio),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen<AsyncValue<VrchatStatusState>>(
        vrchatStatusProvider,
        (_, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container.read(vrchatStatusProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      verify(
        () => mockDio.get(any(), options: any(named: 'options')),
      ).called(1);

      final authNotifier =
          container.read(authProvider.notifier) as _TestAuthNotifier;
      authNotifier.setData(const AuthState(status: AuthStatus.unauthenticated));
      await Future<void>.delayed(Duration.zero);

      responseCompleter.complete(_statusResponse());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(vrchatStatusProvider).value!;
      expect(state.isLoading, isTrue);
      expect(state.errorMessage, isNull);
      expect(state.status == null && !state.isLoading, isFalse);
    },
  );

  test(
    'in-flight failure completion after logout does not overwrite unauthenticated safe state',
    () async {
      final mockDio = _MockDio();
      final responseCompleter = Completer<dio.Response<Map<String, dynamic>>>();
      when(
        () => mockDio.get(any(), options: any(named: 'options')),
      ).thenAnswer((_) => responseCompleter.future);
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
          dioProvider.overrideWith((ref) => mockDio),
        ],
      );
      addTearDown(container.dispose);

      final subscription = container.listen<AsyncValue<VrchatStatusState>>(
        vrchatStatusProvider,
        (_, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      container.read(vrchatStatusProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      verify(
        () => mockDio.get(any(), options: any(named: 'options')),
      ).called(1);

      final authNotifier =
          container.read(authProvider.notifier) as _TestAuthNotifier;
      authNotifier.setData(const AuthState(status: AuthStatus.unauthenticated));
      await Future<void>.delayed(Duration.zero);

      responseCompleter.completeError(
        Exception('network failure'),
        StackTrace.current,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(vrchatStatusProvider).value!;
      expect(state.isLoading, isTrue);
      expect(state.errorMessage, isNull);
      expect(state.status == null && !state.isLoading, isFalse);
    },
  );

  test(
    'refresh timer is cancelled when auth becomes unauthenticated',
    () async {
      final mockDio = _MockDio();
      when(
        () => mockDio.get(any(), options: any(named: 'options')),
      ).thenAnswer((_) async => _statusResponse());
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
          dioProvider.overrideWith((ref) => mockDio),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen<AsyncValue<VrchatStatusState>>(
        vrchatStatusProvider,
        (_, next) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final notifier = container.read(vrchatStatusProvider.notifier);
      final authNotifier =
          container.read(authProvider.notifier) as _TestAuthNotifier;
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.hasActiveRefreshTimer, isTrue);

      authNotifier.setData(const AuthState(status: AuthStatus.unauthenticated));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notifier.hasActiveRefreshTimer, isFalse);
    },
  );

  test('unauthenticated transition keeps state UI-safe', () async {
    final mockDio = _MockDio();
    when(
      () => mockDio.get(any(), options: any(named: 'options')),
    ).thenAnswer((_) async => _statusResponse());
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
        dioProvider.overrideWith((ref) => mockDio),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen<AsyncValue<VrchatStatusState>>(
      vrchatStatusProvider,
      (_, next) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final authNotifier =
        container.read(authProvider.notifier) as _TestAuthNotifier;
    container.read(vrchatStatusProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    authNotifier.setData(const AuthState(status: AuthStatus.unauthenticated));
    await Future<void>.delayed(Duration.zero);

    final state = container.read(vrchatStatusProvider).value!;
    expect(state.status == null && !state.isLoading, isFalse);
  });
}
