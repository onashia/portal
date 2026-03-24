import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vrchat_dart/vrchat_dart.dart';

import '../constants/app_constants.dart';
import '../services/auth_service.dart';
import '../services/two_factor_auth_service.dart';
import 'app_version_provider.dart';
import 'portal_api_request_runner_provider.dart';

enum AuthStatus {
  initial,
  loading,
  requires2FA,
  authenticated,
  unauthenticated,
  error,
  requiresEmailVerification,
}

@immutable
class AuthState {
  static const Object _unset = Object();

  final AuthStatus status;
  final String? errorMessage;
  final CurrentUser? currentUser;
  final StreamedCurrentUser? streamedUser;
  final bool requiresTwoFactorAuth;
  final TwoFactorAuthType? selectedTwoFactorMethod;

  const AuthState({
    required this.status,
    this.errorMessage,
    this.currentUser,
    this.streamedUser,
    this.requiresTwoFactorAuth = false,
    this.selectedTwoFactorMethod,
  });

  AuthState copyWith({
    AuthStatus? status,
    Object? errorMessage = _unset,
    Object? currentUser = _unset,
    Object? streamedUser = _unset,
    bool? requiresTwoFactorAuth,
    Object? selectedTwoFactorMethod = _unset,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      currentUser: identical(currentUser, _unset)
          ? this.currentUser
          : currentUser as CurrentUser?,
      streamedUser: identical(streamedUser, _unset)
          ? this.streamedUser
          : streamedUser as StreamedCurrentUser?,
      requiresTwoFactorAuth:
          requiresTwoFactorAuth ?? this.requiresTwoFactorAuth,
      selectedTwoFactorMethod: identical(selectedTwoFactorMethod, _unset)
          ? this.selectedTwoFactorMethod
          : selectedTwoFactorMethod as TwoFactorAuthType?,
    );
  }
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  late final AuthService _authService;
  late final TwoFactorAuthService _twoFactorAuthService;

  @override
  AuthState build() {
    final api = ref.read(vrchatApiProvider);
    final runner = ref.read(portalApiRequestRunnerProvider);
    _authService = AuthService(api, runner: runner);
    _twoFactorAuthService = TwoFactorAuthService(api, runner: runner);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkExistingSession();
    });

    return AuthState(status: AuthStatus.initial);
  }

  Future<void> login(String username, String password) async {
    state = const AsyncData(AuthState(status: AuthStatus.loading));

    final result = await _authService.login(username, password);

    // Handle all possible authentication outcomes
    // VRChat API may require 2FA, email verification, or fail with error
    switch (result.status) {
      case AuthResultStatus.success:
        state = AsyncData(
          AuthState(
            status: AuthStatus.authenticated,
            currentUser: result.currentUser,
          ),
        );
        break;
      case AuthResultStatus.requires2FA:
        state = AsyncData(
          AuthState(
            status: AuthStatus.requires2FA,
            requiresTwoFactorAuth: true,
            selectedTwoFactorMethod: result.selectedTwoFactorMethod,
          ),
        );
        break;
      case AuthResultStatus.requiresEmailVerification:
        state = AsyncData(
          AuthState(
            status: AuthStatus.requiresEmailVerification,
            errorMessage: result.errorMessage,
          ),
        );
        break;
      case AuthResultStatus.failure:
        state = AsyncData(
          AuthState(
            status: AuthStatus.error,
            errorMessage: result.errorMessage,
          ),
        );
        break;
    }
  }

  Future<void> verify2FA(String code) async {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }

    final selectedMethod = current.selectedTwoFactorMethod;
    if (selectedMethod == null) {
      state = AsyncData(
        current.copyWith(
          status: AuthStatus.requires2FA,
          errorMessage:
              '2FA verification failed: Could not determine verification method',
        ),
      );
      return;
    }

    state = AsyncData(
      current.copyWith(status: AuthStatus.loading, errorMessage: null),
    );

    final result = await _twoFactorAuthService.verify2FA(
      code,
      method: selectedMethod,
    );

    if (result.status == TwoFactorAuthResultStatus.success) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: result.currentUser,
        ),
      );
    } else {
      state = AsyncData(
        current.copyWith(
          status: AuthStatus.requires2FA,
          errorMessage: result.errorMessage,
        ),
      );
    }
  }

  Future<void> logout() async {
    await _authService.logout();

    state = AsyncData(AuthState(status: AuthStatus.initial));
  }

  Future<void> checkExistingSession() async {
    state = AsyncLoading();

    final result = await _authService.checkExistingSession();

    if (result.status == AuthResultStatus.success) {
      state = AsyncData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: result.currentUser,
        ),
      );
    } else {
      state = AsyncData(AuthState(status: AuthStatus.unauthenticated));
    }
  }

  void updateCurrentUser(StreamedCurrentUser user) {
    final current = state.asData?.value;
    if (current == null || current.status != AuthStatus.authenticated) {
      return;
    }

    state = AsyncData(current.copyWith(streamedUser: user));
  }
}

final vrchatApiProvider = Provider<VrchatDart>((ref) {
  final appVersion = ref.read(appVersionProvider);
  // Single shared API instance for the entire application
  // This ensures authentication state is shared across all providers
  final api = VrchatDart(
    userAgent: VrchatUserAgent(
      applicationName: 'portal.',
      version: appVersion,
      contactInfo: 'https://github.com/onashia/portal',
    ),
  );
  api.rawApi.dio.options.connectTimeout = Duration(
    seconds: AppConstants.vrchatApiConnectTimeoutSeconds,
  );
  api.rawApi.dio.options.receiveTimeout = Duration(
    seconds: AppConstants.vrchatApiReceiveTimeoutSeconds,
  );
  return api;
});

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

typedef AuthAsyncMeta = ({bool isLoading, bool hasError, Object? error});
typedef AuthSessionSnapshot = ({
  AuthStatus? status,
  bool isAuthenticated,
  String? userId,
});

final authStatusProvider = Provider<AuthStatus?>((ref) {
  return ref.watch(authProvider.select((value) => value.asData?.value.status));
});

final authCurrentUserProvider = Provider<CurrentUser?>((ref) {
  return ref.watch(
    authProvider.select((value) => value.asData?.value.currentUser),
  );
});

final authSessionSnapshotProvider = Provider<AuthSessionSnapshot>((ref) {
  final rawSession = ref.watch(
    authProvider.select(
      (value) => (
        status: value.asData?.value.status,
        userId: value.asData?.value.currentUser?.id,
      ),
    ),
  );

  final isAuthenticated = rawSession.status == AuthStatus.authenticated;
  return (
    status: rawSession.status,
    isAuthenticated: isAuthenticated,
    userId: isAuthenticated ? rawSession.userId : null,
  );
});

final authStreamedUserProvider = Provider<StreamedCurrentUser?>((ref) {
  return ref.watch(
    authProvider.select((value) => value.asData?.value.streamedUser),
  );
});

final authAsyncMetaProvider = Provider<AuthAsyncMeta>((ref) {
  final authValue = ref.watch(authProvider);
  return (
    isLoading: authValue.isLoading,
    hasError: authValue.hasError,
    error: authValue.error,
  );
});

final authListenableProvider = Provider<ChangeNotifier>((ref) {
  return _AuthChangeNotifier(ref);
});

class _AuthChangeNotifier extends ChangeNotifier {
  final Ref _ref;

  _AuthChangeNotifier(this._ref) {
    _ref.listen<AuthStatus?>(authStatusProvider, (previous, next) {
      if (previous != next) {
        notifyListeners();
      }
    });
  }
}
