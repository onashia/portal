import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    const ProviderScope(
      child: PortalApp(),
    ),
  );
}

class PortalApp extends ConsumerWidget {
  const PortalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final authState = ref.watch(authProvider);

    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) {
        if (authState.status == AuthStatus.authenticated) {
          if (state.matchedLocation == '/') {
            return '/dashboard';
          }
        } else {
          if (state.matchedLocation == '/dashboard') {
            return '/';
          }
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => MaterialPage(
                key: state.pageKey,
                child: const LoginPage(),
              ),
        ),
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) => MaterialPage(
                key: state.pageKey,
                child: const DashboardPage(),
              ),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
