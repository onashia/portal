import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/vrchat_status_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/dashboard/dashboard_user_card.dart';
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

class _TestVrchatStatusNotifier extends VrchatStatusNotifier {
  _TestVrchatStatusNotifier(this._initialState);

  final VrchatStatusState _initialState;

  @override
  VrchatStatusState build() => _initialState;
}

class _MockCurrentUser extends Mock implements CurrentUser {}

class _MockStreamedCurrentUser extends Mock implements StreamedCurrentUser {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'DashboardUserCard reflects streamed user updates without new input props',
    (tester) async {
      final currentUser = _mockCurrentUser(
        displayName: 'Current Name',
        pronouns: 'they/them',
        statusDescription: 'Current status',
        status: UserStatus.active,
      );
      final streamedUser = _mockStreamedCurrentUser(
        displayName: 'Stream Name',
        statusDescription: 'Stream status',
        status: UserStatus.joinMe,
      );

      final authNotifier = _TestAuthNotifier(
        AuthState(status: AuthStatus.authenticated, currentUser: currentUser),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => authNotifier),
            vrchatStatusProvider.overrideWith(
              () => _TestVrchatStatusNotifier(
                const VrchatStatusState(
                  isLoading: false,
                  errorMessage: 'offline',
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: DashboardUserCard(currentUser: currentUser)),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Current Name'), findsOneWidget);
      expect(find.text('they/them • Current status'), findsOneWidget);

      authNotifier.setData(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: currentUser,
          streamedUser: streamedUser,
        ),
      );
      await tester.pump();

      expect(find.text('Current Name'), findsNothing);
      expect(find.text('Stream Name'), findsOneWidget);
      expect(find.text('they/them • Stream status'), findsOneWidget);
    },
  );
}

CurrentUser _mockCurrentUser({
  required String displayName,
  required String pronouns,
  required String statusDescription,
  required UserStatus status,
}) {
  final user = _MockCurrentUser();
  when(() => user.displayName).thenReturn(displayName);
  when(() => user.pronouns).thenReturn(pronouns);
  when(() => user.statusDescription).thenReturn(statusDescription);
  when(() => user.status).thenReturn(status);
  when(() => user.profilePicOverrideThumbnail).thenReturn('');
  when(() => user.currentAvatarThumbnailImageUrl).thenReturn('');
  return user;
}

StreamedCurrentUser _mockStreamedCurrentUser({
  required String displayName,
  required String statusDescription,
  required UserStatus status,
}) {
  final user = _MockStreamedCurrentUser();
  when(() => user.displayName).thenReturn(displayName);
  when(() => user.statusDescription).thenReturn(statusDescription);
  when(() => user.status).thenReturn(status);
  when(() => user.profilePicOverride).thenReturn('');
  when(() => user.currentAvatarThumbnailImageUrl).thenReturn('');
  return user;
}
