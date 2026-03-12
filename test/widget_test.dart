import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portal/main.dart';
import 'package:portal/providers/auth_provider.dart';
import 'test_helpers/auth_test_harness.dart';

void main() {
  testWidgets('Portal app loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            () => TestAuthNotifier(const AuthState(status: AuthStatus.initial)),
          ),
        ],
        child: const PortalApp(),
      ),
    );

    await tester.pump();

    expect(find.text('portal.'), findsOneWidget);
  });
}
