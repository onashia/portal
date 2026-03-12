import 'package:flutter/material.dart';

import '../auth/auth_page_shell.dart';
import '../common/loading_state.dart';

class LoginLoadingScaffold extends StatelessWidget {
  const LoginLoadingScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return const AuthLoadingScaffold(
      showBranding: false,
      body: LoadingState(semanticLabel: 'Loading portal', scale: 2.0),
    );
  }
}
