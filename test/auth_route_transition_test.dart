import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portal/main.dart';
import 'package:portal/providers/auth_provider.dart';

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._initialState);

  final AuthState _initialState;

  @override
  AuthState build() => _initialState;
}

void main() {
  testWidgets(
    'auth routes use custom fade-through transition with symmetric 300ms durations',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () =>
                _TestAuthNotifier(const AuthState(status: AuthStatus.initial)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      final routes = router.configuration.routes.whereType<GoRoute>();
      final loginRoute = routes.firstWhere((route) => route.path == '/');
      final dashboardRoute = routes.firstWhere(
        (route) => route.path == '/dashboard',
      );

      final loginState = GoRouterState(
        router.configuration,
        uri: Uri.parse('/'),
        matchedLocation: '/',
        fullPath: '/',
        pathParameters: const {},
        pageKey: const ValueKey<String>('login'),
        topRoute: loginRoute,
      );
      final dashboardState = GoRouterState(
        router.configuration,
        uri: Uri.parse('/dashboard'),
        matchedLocation: '/dashboard',
        fullPath: '/dashboard',
        pathParameters: const {},
        pageKey: const ValueKey<String>('dashboard'),
        topRoute: dashboardRoute,
      );

      final loginPage = loginRoute.pageBuilder!(context, loginState);
      final dashboardPage = dashboardRoute.pageBuilder!(
        context,
        dashboardState,
      );

      expect(loginPage, isA<CustomTransitionPage<void>>());
      expect(dashboardPage, isA<CustomTransitionPage<void>>());

      final loginTransitionPage = loginPage as CustomTransitionPage<void>;
      final dashboardTransitionPage =
          dashboardPage as CustomTransitionPage<void>;

      expect(
        loginTransitionPage.transitionDuration,
        const Duration(milliseconds: 300),
      );
      expect(
        loginTransitionPage.reverseTransitionDuration,
        const Duration(milliseconds: 300),
      );
      expect(
        dashboardTransitionPage.transitionDuration,
        const Duration(milliseconds: 300),
      );
      expect(
        dashboardTransitionPage.reverseTransitionDuration,
        const Duration(milliseconds: 300),
      );

      final transitionRoot = loginTransitionPage.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(0.5),
        const AlwaysStoppedAnimation<double>(0.0),
        const SizedBox(),
      );

      expect(transitionRoot, isA<FadeTransition>());

      final outerFade = transitionRoot as FadeTransition;
      expect(outerFade.child, isA<FadeTransition>());

      final innerFade = outerFade.child! as FadeTransition;
      expect(innerFade.child, isA<ScaleTransition>());
      expect(innerFade.opacity, isA<CurvedAnimation>());

      final incomingOpacity = innerFade.opacity as CurvedAnimation;
      expect(incomingOpacity.curve, Curves.easeOutCubic);
      expect(incomingOpacity.reverseCurve, Curves.easeInCubic);

      final scaleTransition = innerFade.child! as ScaleTransition;
      expect(scaleTransition.scale, isA<Animation<double>>());
    },
  );
}
