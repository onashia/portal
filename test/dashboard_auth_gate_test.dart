import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/pages/dashboard_page.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

class _MockCurrentUser extends Mock implements CurrentUser {}

void main() {
  group('resolveDashboardAuthViewState', () {
    const loadingMeta = (isLoading: true, hasError: false, error: null);
    const errorMeta = (isLoading: false, hasError: true, error: 'boom');
    const stableMeta = (isLoading: false, hasError: false, error: null);

    test('returns loading when async auth is loading', () {
      final result = resolveDashboardAuthViewState(
        authMeta: loadingMeta,
        authStatus: AuthStatus.initial,
        currentUser: null,
      );

      expect(result, DashboardAuthViewState.loading);
    });

    test('returns error when async auth has error', () {
      final result = resolveDashboardAuthViewState(
        authMeta: errorMeta,
        authStatus: AuthStatus.authenticated,
        currentUser: null,
      );

      expect(result, DashboardAuthViewState.error);
    });

    test('returns handoff for unauthenticated user without current user', () {
      final result = resolveDashboardAuthViewState(
        authMeta: stableMeta,
        authStatus: AuthStatus.unauthenticated,
        currentUser: null,
      );

      expect(result, DashboardAuthViewState.handoff);
    });

    test('returns handoff for initial status without current user', () {
      final result = resolveDashboardAuthViewState(
        authMeta: stableMeta,
        authStatus: AuthStatus.initial,
        currentUser: null,
      );

      expect(result, DashboardAuthViewState.handoff);
    });

    test(
      'returns loading when authenticated status has no current user yet',
      () {
        final result = resolveDashboardAuthViewState(
          authMeta: stableMeta,
          authStatus: AuthStatus.authenticated,
          currentUser: null,
        );

        expect(result, DashboardAuthViewState.loading);
      },
    );

    test('returns ready when current user is available', () {
      final result = resolveDashboardAuthViewState(
        authMeta: stableMeta,
        authStatus: AuthStatus.authenticated,
        currentUser: _MockCurrentUser(),
      );

      expect(result, DashboardAuthViewState.ready);
    });
  });
}
