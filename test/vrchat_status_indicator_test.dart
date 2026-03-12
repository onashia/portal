import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:portal/models/vrchat_status.dart';
import 'package:portal/providers/vrchat_status_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/vrchat/vrchat_status_indicator.dart';
import 'test_helpers/provider_test_notifiers.dart';

void main() {
  testWidgets('incident cards use zero margin and consistent section spacing', (
    tester,
  ) async {
    final now = DateTime.now();
    final status = VrchatStatus(
      description: 'Partially Degraded Service',
      indicator: VrchatStatusIndicator.minor,
      serviceGroups: [
        const VrchatServiceGroup(
          name: 'API / Website',
          status: 'degraded_performance',
          services: [
            VrchatServiceStatus(
              name: 'Authentication / Login',
              status: 'operational',
            ),
            VrchatServiceStatus(
              name: 'Realtime Player State Changes',
              status: 'degraded_performance',
            ),
          ],
        ),
        const VrchatServiceGroup(
          name: 'Realtime Networking',
          status: 'operational',
          services: [
            VrchatServiceStatus(name: 'Japan (Tokyo)', status: 'operational'),
          ],
        ),
      ],
      activeIncidents: [
        Incident(
          id: 'inc_1',
          name: 'API Performance Issues',
          status: IncidentStatus.investigating,
          impact: 'major',
          updates: [
            IncidentUpdate(
              status: IncidentStatus.investigating,
              body:
                  'We are aware of and are investigating increased latency and error rates.',
              createdAt: now.subtract(const Duration(hours: 7)),
            ),
          ],
          createdAt: now.subtract(const Duration(hours: 7)),
        ),
        Incident(
          id: 'inc_2',
          name: 'Friends List Delays',
          status: IncidentStatus.monitoring,
          impact: 'minor',
          updates: [
            IncidentUpdate(
              status: IncidentStatus.monitoring,
              body: 'Fix deployed and we are observing stability.',
              createdAt: now.subtract(const Duration(hours: 2)),
            ),
          ],
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
      ],
      lastUpdated: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vrchatStatusProvider.overrideWith(
            () => TestVrchatStatusNotifier(
              VrchatStatusState(status: status, isLoading: false),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: VrchatStatusWidget())),
        ),
      ),
    );

    await tester.tap(find.byType(VrchatStatusWidget));
    await tester.pumpAndSettle();

    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(cards, hasLength(2));
    for (final card in cards) {
      expect(card.margin, EdgeInsets.zero);
    }

    final spacing = tester.element(find.byType(AlertDialog)).m3e.spacing;
    final firstCardRect = tester.getRect(
      find.ancestor(
        of: find.text('API Performance Issues'),
        matching: find.byType(Card),
      ),
    );
    final secondCardRect = tester.getRect(
      find.ancestor(
        of: find.text('Friends List Delays'),
        matching: find.byType(Card),
      ),
    );
    final interCardGap = secondCardRect.top - firstCardRect.bottom;
    expect(interCardGap, moreOrLessEquals(spacing.sm, epsilon: 0.1));

    final lastUpdatedRect = tester.getRect(
      find.textContaining('Last updated:'),
    );
    final footerGap = lastUpdatedRect.top - secondCardRect.bottom;
    expect(footerGap, moreOrLessEquals(spacing.md, epsilon: 0.1));
  });

  testWidgets('incident meta content aligns with incident title text column', (
    tester,
  ) async {
    final now = DateTime.now();
    final status = VrchatStatus(
      description: 'Partially Degraded Service',
      indicator: VrchatStatusIndicator.minor,
      serviceGroups: const [
        VrchatServiceGroup(
          name: 'API / Website',
          status: 'degraded_performance',
          services: [
            VrchatServiceStatus(
              name: 'Authentication / Login',
              status: 'operational',
            ),
          ],
        ),
      ],
      activeIncidents: [
        Incident(
          id: 'inc_1',
          name: 'API Performance Issues',
          status: IncidentStatus.investigating,
          impact: 'major',
          updates: [
            IncidentUpdate(
              status: IncidentStatus.investigating,
              body: 'Investigating increased latency and error rates.',
              createdAt: now.subtract(const Duration(hours: 3)),
            ),
          ],
          createdAt: now.subtract(const Duration(hours: 3)),
        ),
      ],
      lastUpdated: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vrchatStatusProvider.overrideWith(
            () => TestVrchatStatusNotifier(
              VrchatStatusState(status: status, isLoading: false),
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: Center(child: VrchatStatusWidget())),
        ),
      ),
    );

    await tester.tap(find.byType(VrchatStatusWidget));
    await tester.pumpAndSettle();

    final titleDx = tester.getTopLeft(find.text('API Performance Issues')).dx;
    final statusDx = tester.getTopLeft(find.text('Investigating')).dx;
    final bodyDx = tester
        .getTopLeft(
          find.text('Investigating increased latency and error rates.'),
        )
        .dx;

    expect(statusDx, moreOrLessEquals(titleDx, epsilon: 0.1));
    expect(bodyDx, moreOrLessEquals(titleDx, epsilon: 0.1));
  });
}
