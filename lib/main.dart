import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'constants/storage_keys.dart';
import 'providers/auth_provider.dart';
import 'providers/pipeline_provider.dart';
import 'providers/theme_provider.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'theme/app_theme.dart';
import 'utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 1: Load theme preference BEFORE app starts
  try {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString(StorageKeys.themeMode);

    final initialTheme = ThemeMode.values.firstWhere(
      (mode) => mode.name == themeString,
      orElse: () => ThemeMode.system,
    );
    ThemeNotifier.setInitialTheme(initialTheme);
  } catch (e) {
    AppLogger.error('Failed to load theme', error: e);
    ThemeNotifier.setInitialTheme(ThemeMode.system);
  }

  // Phase 2: Window manager initialization
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitle('portal.');
      await windowManager.setSize(const Size(1200, 800));
      await windowManager.setMinimumSize(const Size(800, 600));
      await windowManager.center();
      await windowManager.setAsFrameless();
      await windowManager.setResizable(true);
      await windowManager.show();
    });
  }

  runApp(ProviderScope(child: PortalApp()));
}

final routerProvider = Provider<GoRouter>((ref) {
  final authListenable = ref.watch(authListenableProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authListenable,
    // Authentication guard: redirect based on auth state
    redirect: (context, state) {
      final authValue = ref.read(authProvider);
      if (authValue.value?.status == AuthStatus.authenticated) {
        // Authenticated users cannot stay on login page
        if (state.matchedLocation == '/') {
          return '/dashboard';
        }
      } else {
        // Unauthenticated users cannot access dashboard
        if (state.matchedLocation == '/dashboard') {
          return '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) =>
            MaterialPage(key: state.pageKey, child: const LoginPage()),
      ),
      GoRoute(
        path: '/dashboard',
        pageBuilder: (context, state) =>
            MaterialPage(key: state.pageKey, child: const DashboardPage()),
      ),
    ],
  );
});

class PortalApp extends ConsumerWidget {
  const PortalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final router = ref.watch(routerProvider);
    ref.watch(pipelineEventHandlerProvider);

    return MaterialApp.router(
      title: 'portal.',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
