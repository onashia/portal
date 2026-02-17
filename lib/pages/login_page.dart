import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/ui_constants.dart';
import '../providers/auth_provider.dart';
import '../utils/error_utils.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/login/login_submit_button.dart';
import '../widgets/login/login_back_button.dart';
import '../widgets/login/login_error_message.dart';
import '../widgets/login/login_branding.dart';
import '../widgets/login/login_form_card.dart';
import '../widgets/login/login_form_fields.dart';
import '../widgets/login/login_scaffolds.dart';
import '../widgets/login/login_theme_toggle.dart';
import '../widgets/login/two_factor_form_fields.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _twoFactorController = TextEditingController();
  final _obscurePassword = ValueNotifier<bool>(true);
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _twoFactorFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _usernameFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _twoFactorController.dispose();
    _obscurePassword.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _twoFactorFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final authState = ref.read(authProvider).value;
    if (authState == null) return;

    final username = _usernameController.text;
    final password = _passwordController.text;
    final code = _twoFactorController.text;
    final requiresTwoFactor = authState.requiresTwoFactorAuth;

    if (requiresTwoFactor) {
      await ref.read(authProvider.notifier).verify2FA(code);
      if (!mounted) return;
      final newState = ref.read(authProvider).value;
      if (newState?.status == AuthStatus.authenticated) {
        _twoFactorController.clear();
      }
    } else {
      await ref.read(authProvider.notifier).login(username, password);
      if (!mounted) return;
      final newState = ref.read(authProvider).value;
      if (newState?.status == AuthStatus.authenticated) {
        _passwordController.clear();
      }
    }
  }

  double _getCardWidth(double screenWidth) {
    if (screenWidth < UiConstants.loginBreakpointXs) {
      return screenWidth - UiConstants.loginSmallScreenMargin;
    }
    if (screenWidth < UiConstants.loginBreakpointSm) {
      return UiConstants.loginCardWidthSm;
    }
    if (screenWidth < UiConstants.loginBreakpointMd) {
      return UiConstants.loginCardWidthMd;
    }
    if (screenWidth < UiConstants.loginBreakpointLg) {
      return UiConstants.loginCardWidthLg;
    }
    return UiConstants.loginCardWidthXl;
  }

  @override
  Widget build(BuildContext context) {
    final authValue = ref.watch(authProvider);

    if (authValue.isLoading) {
      return const LoginLoadingScaffold();
    }

    if (authValue.hasError) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: CustomTitleBar(
          title: 'portal.',
          icon: Icons.tonality,
          showBranding: false,
          actions: const [LoginThemeToggle()],
        ),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'An error occurred',
          message: formatUiErrorMessage(authValue.error),
          iconColor: scheme.error,
          padding: EdgeInsets.all(context.m3e.spacing.lg),
        ),
      );
    }

    final authState = authValue.value;
    if (authState == null) {
      return const SizedBox.shrink();
    }
    final passwordErrorMessage =
        authState.status == AuthStatus.error ||
            authState.status == AuthStatus.requiresEmailVerification
        ? authState.errorMessage
        : null;

    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [LoginThemeToggle()],
      ),
      body: DragToResizeArea(
        child: Semantics(
          label: 'Login form for VRChat portal',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = _getCardWidth(constraints.maxWidth);
              final shiftAmount = UiConstants.loginLogoVisualHeight / 2;

              final formBody = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!authState.requiresTwoFactorAuth)
                    LoginFormFields(
                      usernameController: _usernameController,
                      passwordController: _passwordController,
                      usernameFocusNode: _usernameFocusNode,
                      passwordFocusNode: _passwordFocusNode,
                      obscurePassword: _obscurePassword,
                      errorMessage: passwordErrorMessage,
                      errorMessageWidget: LoginErrorMessage(
                        passwordErrorMessage,
                      ),
                    )
                  else
                    TwoFactorFormFields(
                      controller: _twoFactorController,
                      focusNode: _twoFactorFocusNode,
                      errorMessage: authState.errorMessage,
                      onSubmit: _handleSubmit,
                      errorMessageWidget: LoginErrorMessage(
                        authState.errorMessage,
                      ),
                    ),
                  if (authState.requiresTwoFactorAuth)
                    SizedBox(height: context.m3e.spacing.lg),
                  LoginSubmitButton(
                    authState: authState,
                    onPressed: _handleSubmit,
                  ),
                  if (authState.requiresTwoFactorAuth)
                    Padding(
                      padding: EdgeInsets.only(top: context.m3e.spacing.md),
                      child: LoginBackButton(
                        onPressed: () {
                          _passwordController.clear();
                          ref.read(authProvider.notifier).logout();
                          _twoFactorController.clear();
                        },
                      ),
                    ),
                ],
              );

              return Center(
                child: Transform.translate(
                  offset: Offset(0, -shiftAmount),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(context.m3e.spacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LoginBranding(),
                        LoginFormCard(
                          authState: authState,
                          formKey: _formKey,
                          formBody: formBody,
                          cardWidth: cardWidth,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
