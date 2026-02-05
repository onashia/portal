import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:motor/motor.dart';
import 'package:m3e_collection/m3e_collection.dart';
import 'package:pinput/pinput.dart';
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
                  SizedBox(width: context.m3e.spacing.md),
                  Text(
                    'portal.',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              SizedBox(height: context.m3e.spacing.lg),
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
                suffixIcon: IconButtonM3E(
                  icon: const Icon(Icons.visibility),
                  selectedIcon: const Icon(Icons.visibility_off),
                  isSelected: obscure,
                  onPressed: () => _obscurePassword.value = !obscure,
                  tooltip: obscure ? 'Show password' : 'Hide password',
                  variant: IconButtonM3EVariant.standard,
                  size: IconButtonM3ESize.sm,
                  shape: IconButtonM3EShapeVariant.round,
                ),
                errorText: isErrorState ? errorMessage : null,
                errorStyle: isErrorState
                    ? const TextStyle(height: 0, fontSize: 0)
                    : null,
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final baseDecoration = BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: context.m3e.shapes.square.lg,
      border: Border.all(color: scheme.surfaceContainerHighest, width: 1),
    );
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
      decoration: baseDecoration,
    );
    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: baseDecoration.copyWith(
        border: Border.all(color: scheme.primary, width: 2),
      ),
    );
    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: baseDecoration.copyWith(
        border: Border.all(color: scheme.error, width: 2),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Pinput(
          controller: _twoFactorController,
          focusNode: _twoFactorFocusNode,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          length: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _handleSubmit(),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your verification code';
            }
            if (!RegExp(r'^\d{6}$').hasMatch(value)) {
              return 'Code must be exactly 6 digits';
            }
            return null;
          },
          forceErrorState: isErrorState,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          errorPinTheme: errorPinTheme,
          submittedPinTheme: defaultPinTheme,
          separatorBuilder: (_) => SizedBox(width: context.m3e.spacing.md),
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

    return ButtonM3E(
      onPressed: isLoading ? null : onPressed,
      label: isLoading
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : Text(text),
      style: ButtonM3EStyle.filled,
      size: ButtonM3ESize.md,
      shape: ButtonM3EShape.square,
    );
  }

  Widget _buildBackButton(VoidCallback onPressed) {
    return ButtonM3E(
      onPressed: onPressed,
      label: const Text('Back to login'),
      style: ButtonM3EStyle.text,
      size: ButtonM3ESize.sm,
      shape: ButtonM3EShape.square,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authValue = ref.watch(authProvider);

    return authValue.when(
      loading: () => const _LoadingScaffold(),
      error: (error, stack) => _ErrorScaffold(error: error, stack: stack),
      data: (authState) => Scaffold(
        appBar: CustomTitleBar(
          title: 'portal.',
          icon: Icons.tonality,
          showBranding: false,
          actions: const [_ThemeToggle()],
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
                      padding: EdgeInsets.all(context.m3e.spacing.lg),
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
                                              SizedBox(
                                                height: context.m3e.spacing.xl,
                                              ),
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
                                                              SizedBox(
                                                                height: context
                                                                    .m3e
                                                                    .spacing
                                                                    .md,
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
                                                              SizedBox(
                                                                height: context
                                                                    .m3e
                                                                    .spacing
                                                                    .lg,
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
                                                              SizedBox(
                                                                height: context
                                                                    .m3e
                                                                    .spacing
                                                                    .lg,
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
                                                            EdgeInsets.only(
                                                              top: context
                                                                  .m3e
                                                                  .spacing
                                                                  .md,
                                                            ),
                                                        child: _buildBackButton(
                                                          () {
                                                            _passwordController
                                                                .clear();
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

class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButtonM3E(
      icon: Icon(
        ref.watch(themeProvider) == ThemeMode.light
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined,
      ),
      tooltip: ref.watch(themeProvider) == ThemeMode.light
          ? 'Dark Mode'
          : 'Light Mode',
      onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
      variant: IconButtonM3EVariant.standard,
      size: IconButtonM3ESize.sm,
      shape: IconButtonM3EShapeVariant.round,
    );
  }
}

class _LoadingScaffold extends ConsumerWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [_ThemeToggle()],
      ),
      body: Center(
        child: Transform.scale(
          scale: 2.0,
          child: const LoadingIndicatorM3E(
            variant: LoadingIndicatorM3EVariant.defaultStyle,
            semanticLabel: 'Loading portal',
          ),
        ),
      ),
    );
  }
}

class _ErrorScaffold extends ConsumerWidget {
  final Object error;
  final StackTrace stack;

  const _ErrorScaffold({required this.error, required this.stack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
        showBranding: false,
        actions: const [_ThemeToggle()],
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(context.m3e.spacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              SizedBox(height: context.m3e.spacing.md),
              Text(
                'An error occurred',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              SizedBox(height: context.m3e.spacing.sm),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String? message;

  const _ErrorMessage(this.message);

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
          padding: EdgeInsets.only(top: context.m3e.spacing.sm),
          child: Text(
            message ?? '',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}
