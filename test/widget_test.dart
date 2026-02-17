import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portal/main.dart';
import 'package:portal/providers/auth_provider.dart';

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(this._initialState);

  final AuthState _initialState;

  @override
  AuthState build() => _initialState;
}

void main() {
  testWidgets('Portal app loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () =>
                _TestAuthNotifier(const AuthState(status: AuthStatus.initial)),
          ),
        ],
        child: const PortalApp(),
      ),
    );

    await tester.pump();

    expect(find.text('portal.'), findsOneWidget);
  });
}
