import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:portal/main.dart';

void main() {
  testWidgets('Portal app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PortalApp()));

    await tester.pump();

    expect(find.text('portal.'), findsOneWidget);
  });
}
