import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/loading_state.dart';
import '../custom_title_bar.dart';
import 'login_theme_toggle.dart';

class LoginLoadingScaffold extends ConsumerWidget {
  const LoginLoadingScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [LoginThemeToggle()],
      ),
      body: const LoadingState(semanticLabel: 'Loading portal', scale: 2.0),
    );
  }
}
