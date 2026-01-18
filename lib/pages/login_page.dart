import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/custom_title_bar.dart';

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
  final _twoFactorErrorCleared = ValueNotifier<bool>(false);
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _twoFactorFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 100), () {
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
    _twoFactorErrorCleared.dispose();
    _fadeController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _twoFactorFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final authState = ref.read(authProvider).value;
    if (authState == null) return;

    if (authState.requiresTwoFactorAuth) {
      final code = _twoFactorController.text;
      await ref.read(authProvider.notifier).verify2FA(code);
      if (!mounted) return;
      _twoFactorController.clear();
      _twoFactorErrorCleared.value = false;
    } else {
      await ref
          .read(authProvider.notifier)
          .login(_usernameController.text, _passwordController.text);
      if (!mounted) return;
      _passwordController.clear();
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
    return FadeTransition(
      opacity: _fadeAnimation,
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
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      focusNode: _usernameFocusNode,
      onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
      decoration: const InputDecoration(
        labelText: 'Username',
        hintText: 'Enter your username',
        prefixIcon: Icon(Icons.person_outline),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your username';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return ValueListenableBuilder(
      valueListenable: _obscurePassword,
      builder: (context, obscure, child) {
        return TextFormField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => _obscurePassword.value = !obscure,
              tooltip: obscure ? 'Show password' : 'Hide password',
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            return null;
          },
        );
      },
    );
  }

  Widget _build2FAField() {
    return TextFormField(
      controller: _twoFactorController,
      focusNode: _twoFactorFocusNode,
      onFieldSubmitted: (_) => _handleSubmit(),
      onChanged: (value) {
        if (_twoFactorErrorCleared.value == false) {
          _twoFactorErrorCleared.value = true;
        }
      },
      decoration: const InputDecoration(
        labelText: 'Authenticator Code',
        hintText: 'Enter 6-digit code',
        prefixIcon: Icon(Icons.security),
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
    );
  }

  Widget _buildErrorMessage(String? errorMessage) {
    if (errorMessage == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.errorContainer.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.error),
          ),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(
    AuthStatus status,
    String text,
    VoidCallback onPressed,
  ) {
    final isLoading = status == AuthStatus.loading;

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        animationDuration: const Duration(milliseconds: 150),
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
          : Text(text),
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
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, 32 * (1 - value)),
                                child: Opacity(
                                  opacity: value,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: cardWidth,
                                    ),
                                    child: Card(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerLow,
                                      elevation: 1,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
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
                                              if (!authState
                                                  .requiresTwoFactorAuth) ...[
                                                _buildUsernameField(),
                                                const SizedBox(height: 16),
                                                _buildPasswordField(),
                                                const SizedBox(height: 16),
                                              ] else
                                                ValueListenableBuilder(
                                                  valueListenable:
                                                      _twoFactorErrorCleared,
                                                  builder: (context, cleared, child) {
                                                    final showErrorMessage =
                                                        authState
                                                                .errorMessage !=
                                                            null &&
                                                        !cleared;
                                                    return Column(
                                                      children: [
                                                        _build2FAField(),
                                                        _buildErrorMessage(
                                                          showErrorMessage
                                                              ? authState
                                                                    .errorMessage
                                                              : null,
                                                        ),
                                                        const SizedBox(
                                                          height: 24,
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              _buildSubmitButton(
                                                authState.status,
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
                                                  .requiresTwoFactorAuth) ...[
                                                const SizedBox(height: 16),
                                                _buildBackButton(() {
                                                  _clearPassword();
                                                  ref
                                                      .read(
                                                        authProvider.notifier,
                                                      )
                                                      .logout();
                                                  _twoFactorController.clear();
                                                }),
                                              ],
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
