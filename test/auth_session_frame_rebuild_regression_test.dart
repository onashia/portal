import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/vrchat_status_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'auth transition from authenticated to logged out does not trigger provider rebuild crash',
    (tester) async {
      final mockDio = _MockDio();
      when(() => mockDio.get(any())).thenAnswer((_) async => _statusResponse());
      final authNotifier = _TestAuthNotifier(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: _mockCurrentUser('usr_test'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(() => authNotifier),
            dioProvider.overrideWith((ref) => mockDio),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, child) {
                // Activate the providers involved in the logout crash path.
                ref.watch(groupMonitorProvider('usr_test'));
                ref.watch(groupCalendarProvider('usr_test'));
                ref.watch(vrchatStatusProvider);

                final session = ref.watch(authSessionSnapshotProvider);
                return Text(session.isAuthenticated ? 'dashboard' : 'login');
              },
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);

      authNotifier.setData(const AuthState(status: AuthStatus.initial));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));

      expect(find.text('login'), findsOneWidget);
      expect(find.text('dashboard'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
