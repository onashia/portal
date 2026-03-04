import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/loading_state.dart';
import '../common/theme_mode_toggle_button.dart';
import '../custom_title_bar.dart';

class LoginLoadingScaffold extends ConsumerWidget {
  const LoginLoadingScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [ThemeModeToggleButton()],
      ),
      body: const LoadingState(semanticLabel: 'Loading portal', scale: 2.0),
    );
  }
}
