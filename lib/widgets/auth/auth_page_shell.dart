import 'package:flutter/material.dart';
import 'package:m3e_collection/m3e_collection.dart';

import '../common/empty_state.dart';
import '../common/theme_mode_toggle_button.dart';
import '../custom_title_bar.dart';

class AuthPageScaffold extends StatelessWidget {
  const AuthPageScaffold({
    super.key,
    required this.body,
    this.showTitleBar = true,
    this.showBranding = true,
    this.actions = const <Widget>[],
  });

  final Widget body;
  final bool showTitleBar;
  final bool showBranding;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showTitleBar
          ? CustomTitleBar(
              title: 'portal.',
              icon: Icons.tonality,
              showBranding: showBranding,
              actions: [const ThemeModeToggleButton(), ...actions],
            )
          : null,
      body: body,
    );
  }
}

class AuthLoadingScaffold extends StatelessWidget {
  const AuthLoadingScaffold({
    super.key,
    required this.body,
    this.showTitleBar = true,
    this.showBranding = true,
    this.actions = const <Widget>[],
  });

  final Widget body;
  final bool showTitleBar;
  final bool showBranding;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      showTitleBar: showTitleBar,
      showBranding: showBranding,
      actions: actions,
      body: body,
    );
  }
}

class AuthErrorScaffold extends StatelessWidget {
  const AuthErrorScaffold({
    super.key,
    required this.message,
    this.showBranding = true,
    this.actions = const <Widget>[],
    this.padding,
  });

  final String message;
  final bool showBranding;
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AuthPageScaffold(
      showBranding: showBranding,
      actions: actions,
      body: EmptyState(
        icon: Icons.error_outline,
        title: 'An error occurred',
        message: message,
        iconColor: scheme.error,
        padding: padding ?? EdgeInsets.all(context.m3e.spacing.lg),
      ),
    );
  }
}
