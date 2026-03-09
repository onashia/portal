import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/pages/dashboard_page.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/custom_title_bar.dart';
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

    testWidgets('handoff surface paints a scaffold background', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: buildDashboardHandoffScaffold()),
      );

      final scaffoldFinder = find.byType(Scaffold);
      final sizedBoxFinder = find.descendant(
        of: scaffoldFinder,
        matching: find.byType(SizedBox),
      );

      expect(scaffoldFinder, findsOneWidget);
      expect(sizedBoxFinder, findsOneWidget);

      final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
      expect(sizedBox.width, double.infinity);
      expect(sizedBox.height, double.infinity);
    });

    testWidgets(
      'dashboard loading state keeps the custom title bar visible',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authAsyncMetaProvider.overrideWithValue(
                (isLoading: true, hasError: false, error: null),
              ),
              authStatusProvider.overrideWithValue(AuthStatus.initial),
              authCurrentUserProvider.overrideWithValue(null),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const DashboardPage(),
            ),
          ),
        );

        expect(find.byType(CustomTitleBar), findsOneWidget);
      },
    );
  });
}
