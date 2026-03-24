import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:portal/providers/app_version_provider.dart';
import 'package:portal/providers/auth_provider.dart';
import 'package:portal/providers/group_calendar_provider.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/providers/vrchat_status_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_helpers/auth_test_harness.dart';

class _MockDio extends Mock implements dio.Dio {}

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
      when(
        () => mockDio.get(any(), options: any(named: 'options')),
      ).thenAnswer((_) async => _statusResponse());
      final authNotifier = TestAuthNotifier(
        AuthState(
          status: AuthStatus.authenticated,
          currentUser: mockCurrentUser('usr_test'),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionProvider.overrideWithValue(testAppVersion),
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
