import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:portal/providers/group_monitor_provider.dart';
import 'package:portal/theme/app_theme.dart';
import 'package:portal/widgets/debug_info_card.dart';
import '../test_helpers/provider_test_notifiers.dart';

void main() {
  testWidgets('renders Boost Last FetchedAt using local time', (tester) async {
    final fetchedAtUtc = DateTime.utc(2026, 2, 13, 14, 15, 16);
    final expected = DateFormat.jms().format(fetchedAtUtc.toLocal());

    final monitorState = GroupMonitorState(
      selectedGroupIds: const {'grp_alpha'},
      lastBoostFetchedAt: fetchedAtUtc,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          groupMonitorProvider(
            'usr_test',
          ).overrideWith(() => TestGroupMonitorNotifier(monitorState)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: DebugInfoCard(userId: 'usr_test')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Boost Last FetchedAt'), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
  });
}
