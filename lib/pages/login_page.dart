import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:motor/motor.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/custom_title_bar.dart';
import '../utils/animation_constants.dart';

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

    try {
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
    } catch (e) {
      if (mounted) {}
    }
  }

  void _clearPassword() {
    _passwordController.clear();
  }

  double _getCardWidth(double screenWidth) {
    if (screenWidth < 400) return screenWidth - 32;
    if (screenWidth < 600) return 280;
    if (screenWidth < 900) return 340;
    if (screenWidth < 1200) return 380;
    return 420;
  }

  Widget _buildBranding() {
    return SingleMotionBuilder(
      motion: AnimationConstants.expressiveEffectsDefault,
      value: 1.0,
      from: 0.0,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.tonality,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'portal.',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      focusNode: _usernameFocusNode,
      onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
      decoration: InputDecoration(
        labelText: 'Username',
        hintText: 'Enter your username',
        prefixIcon: const Icon(Icons.person_outline),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AnimationConstants.borderRadiusLg,
          ),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
            AnimationConstants.borderRadiusLg,
          ),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.tertiary,
            width: 2,
          ),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your username';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField(String? errorMessage) {
    final isErrorState = errorMessage != null;

    return ValueListenableBuilder(
      valueListenable: _obscurePassword,
      builder: (context, obscure, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: AnimationConstants.defaultEnter,
                  switchOutCurve: AnimationConstants.defaultExit,
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: IconButton(
                    key: ValueKey(obscure),
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => _obscurePassword.value = !obscure,
                    tooltip: obscure ? 'Show password' : 'Hide password',
                  ),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AnimationConstants.borderRadiusLg,
                  ),
                  borderSide: BorderSide(
                    color: isErrorState
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    width: isErrorState ? 2 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    AnimationConstants.borderRadiusLg,
                  ),
                  borderSide: BorderSide(
                    color: isErrorState
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.tertiary,
                    width: 2,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
            _ErrorMessage(errorMessage),
          ],
        );
      },
    );
  }

  Widget _build2FAField(String? errorMessage) {
    final isErrorState = errorMessage != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: _twoFactorController,
          focusNode: _twoFactorFocusNode,
          onFieldSubmitted: (_) => _handleSubmit(),
          decoration: InputDecoration(
            labelText: 'Authenticator Code',
            hintText: 'Enter 6-digit code',
            prefixIcon: const Icon(Icons.security),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                AnimationConstants.borderRadiusLg,
              ),
              borderSide: BorderSide(
                color: isErrorState
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                width: isErrorState ? 2 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(
                AnimationConstants.borderRadiusLg,
              ),
              borderSide: BorderSide(
                color: isErrorState
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.tertiary,
                width: 2,
              ),
            ),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your verification code';
            }
            if (!RegExp(r'^\d{6}$').hasMatch(value)) {
              return 'Code must be exactly 6 digits';
            }
            return null;
          },
        ),
        _ErrorMessage(errorMessage),
      ],
    );
  }

  Widget _buildSubmitButton(
    AuthState authState,
    String text,
    VoidCallback onPressed,
  ) {
    final isLoading = authState.isLoading;

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style:
          FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AnimationConstants.borderRadiusLg,
              ),
            ),
            animationDuration: const Duration(milliseconds: 200),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return Theme.of(
                  context,
                ).colorScheme.onPrimary.withValues(alpha: 0.15);
              }
              if (states.contains(WidgetState.hovered)) {
                return Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12);
              }
              return null;
            }),
          ),
      child: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: AnimationConstants.defaultEnter,
              switchOutCurve: AnimationConstants.defaultExit,
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Text(text, key: ValueKey(text)),
            ),
    );
  }

  Widget _buildBackButton(VoidCallback onPressed) {
    return TextButton(onPressed: onPressed, child: const Text('Back to login'));
  }

  @override
  Widget build(BuildContext context) {
    final authValue = ref.watch(authProvider);

    return authValue.when(
      // Initial loading state - occurs when auth provider is initializing
      // or when checking existing session on app startup
      loading: () => Scaffold(
        appBar: CustomTitleBar(
          title: 'portal.',
          icon: Icons.tonality,
          showBranding: false,
          actions: [
            IconButton(
              icon: Icon(
                ref.watch(themeProvider) == ThemeMode.light
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              tooltip: 'Toggle Theme',
              onPressed: () {
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        appBar: CustomTitleBar(
          title: 'portal.',
          icon: Icons.tonality,
          showBranding: false,
          actions: [
            IconButton(
              icon: Icon(
                ref.watch(themeProvider) == ThemeMode.light
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              tooltip: 'Toggle Theme',
              onPressed: () {
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'An error occurred',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
      data: (authState) => Scaffold(
        appBar: CustomTitleBar(
          title: 'portal.',
          icon: Icons.tonality,
          showBranding: false,
          actions: [
            IconButton(
              icon: Icon(
                ref.watch(themeProvider) == ThemeMode.light
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              tooltip: 'Toggle Theme',
              onPressed: () {
                ref.read(themeProvider.notifier).toggleTheme();
              },
            ),
          ],
        ),
        body: DragToResizeArea(
          child: Semantics(
            label: 'Login form for VRChat portal',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = _getCardWidth(constraints.maxWidth);
                const logoVisualHeight = 68;
                final shiftAmount = logoVisualHeight / 2;

                return Center(
                  child: Transform.translate(
                    offset: Offset(0, -shiftAmount),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBranding(),
                          SingleMotionBuilder(
                            key: const ValueKey('loginCardAnimation'),
                            motion: AnimationConstants.expressiveSpatialDefault,
                            value: 1.0,
                            from: 0.0,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(
                                  0,
                                  AnimationConstants.defaultSlideDistance *
                                      (1 - value),
                                ),
                                child: Opacity(
                                  opacity: value.clamp(0.0, 1.0),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: cardWidth,
                                    ),
                                    child: Card(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHigh,
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AnimationConstants.borderRadiusXl,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(32),
                                        child: Form(
                                          key: _formKey,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                authState.requiresTwoFactorAuth
                                                    ? 'Two-Factor Authentication'
                                                    : 'Sign in to your VRChat account',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 32),
                                              SingleMotionBuilder(
                                                motion: AnimationConstants
                                                    .expressiveSpatialDefault,
                                                value: 1.0,
                                                from: 0.0,
                                                key: ValueKey(
                                                  authState
                                                      .requiresTwoFactorAuth,
                                                ),
                                                builder: (context, value, child) {
                                                  return Transform.translate(
                                                    offset: Offset(
                                                      0,
                                                      AnimationConstants
                                                              .defaultSlideDistance *
                                                          (1 - value),
                                                    ),
                                                    child: Opacity(
                                                      opacity: value.clamp(
                                                        0.0,
                                                        1.0,
                                                      ),
                                                      child: child,
                                                    ),
                                                  );
                                                },
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    !authState
                                                            .requiresTwoFactorAuth
                                                        ? Column(
                                                            key: const ValueKey(
                                                              'loginForm',
                                                            ),
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              _buildUsernameField(),
                                                              const SizedBox(
                                                                height: 16,
                                                              ),
                                                              _buildPasswordField(
                                                                (authState.status ==
                                                                            AuthStatus.error ||
                                                                        authState.status ==
                                                                            AuthStatus.requiresEmailVerification)
                                                                    ? authState
                                                                          .errorMessage
                                                                    : null,
                                                              ),
                                                              const SizedBox(
                                                                height: 16,
                                                              ),
                                                            ],
                                                          )
                                                        : Column(
                                                            key: const ValueKey(
                                                              'twoFactorForm',
                                                            ),
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              _build2FAField(
                                                                authState
                                                                    .errorMessage,
                                                              ),
                                                              const SizedBox(
                                                                height: 24,
                                                              ),
                                                            ],
                                                          ),
                                                    _buildSubmitButton(
                                                      authState,
                                                      authState.status ==
                                                              AuthStatus
                                                                  .requiresEmailVerification
                                                          ? 'Retry Login'
                                                          : authState
                                                                .requiresTwoFactorAuth
                                                          ? 'Verify'
                                                          : 'Sign In',
                                                      _handleSubmit,
                                                    ),
                                                    if (authState
                                                        .requiresTwoFactorAuth)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 16,
                                                            ),
                                                        child: _buildBackButton(
                                                          () {
                                                            _clearPassword();
                                                            ref
                                                                .read(
                                                                  authProvider
                                                                      .notifier,
                                                                )
                                                                .logout();
                                                            _twoFactorController
                                                                .clear();
                                                          },
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
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
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String? message;

  const _ErrorMessage(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: AnimationConstants.expressiveSpatialDefault,
      value: message != null ? 1.0 : 0.0,
      builder: (context, value, child) {
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value.clamp(0.0, 1.0),
            child: child,
          ),
        );
      },
      child: Opacity(
        opacity: message != null ? 1.0 : 0.0,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            message ?? '',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
