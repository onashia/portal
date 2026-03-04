import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal/widgets/animated_fade_slide.dart';

void main() {
  Widget buildHarness(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      buildHarness(const AnimatedFadeSlide(child: Text('hello'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('opacity is clamped to 1.0 when value exceeds 1.0', (
    tester,
  ) async {
    // value and from both set to 1.5 so the spring is already settled.
    await tester.pumpWidget(
      buildHarness(
        const AnimatedFadeSlide(value: 1.5, from: 1.5, child: Text('hi')),
      ),
    );
    await tester.pumpAndSettle();

    final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity.opacity, 1.0);
  });

  testWidgets('translate offset is zero when settled at value 1.0', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildHarness(
        const AnimatedFadeSlide(value: 1.0, from: 1.0, child: Text('hi')),
      ),
    );
    await tester.pumpAndSettle();

    final transform = tester.widget<Transform>(find.byType(Transform).first);
    final translation = transform.transform.getTranslation();
    expect(translation.y, 0.0);
  });

  testWidgets(
    'translate offset equals slideDistance when settled at value 0.0',
    (tester) async {
      const distance = 24.0;
      await tester.pumpWidget(
        buildHarness(
          const AnimatedFadeSlide(
            value: 0.0,
            from: 0.0,
            slideDistance: distance,
            child: Text('hi'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final transform = tester.widget<Transform>(find.byType(Transform).first);
      final translation = transform.transform.getTranslation();
      expect(translation.y, distance);
    },
  );
}
