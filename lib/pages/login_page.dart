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

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _twoFactorController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _twoFactorController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final authState = ref.read(authProvider);

    if (authState.requiresTwoFactorAuth) {
      await ref
          .read(authProvider.notifier)
          .verify2FA(_twoFactorController.text);
    } else {
      await ref
          .read(authProvider.notifier)
          .login(_usernameController.text, _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: CustomTitleBar(
        title: 'portal.',
        icon: Icons.tonality,
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.tonality,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          authState.requiresTwoFactorAuth
                              ? 'Two-Factor Authentication'
                              : 'Welcome to Portal',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          authState.requiresTwoFactorAuth
                              ? 'Enter your verification code'
                              : 'Sign in to your VRChat account',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        if (!authState.requiresTwoFactorAuth) ...[
                          TextFormField(
                            controller: _usernameController,
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
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              hintText: 'Enter your password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                        ] else
                          TextFormField(
                            controller: _twoFactorController,
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
                              if (value.length != 6) {
                                return 'Code must be 6 digits';
                              }
                              return null;
                            },
                          ),
                        if (authState.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.error,
                              ),
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
                                    authState.errorMessage!,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: authState.status == AuthStatus.loading
                              ? null
                              : _handleSubmit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: authState.status == AuthStatus.loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  authState.status ==
                                          AuthStatus.requiresEmailVerification
                                      ? 'Retry Login'
                                      : authState.requiresTwoFactorAuth
                                      ? 'Verify'
                                      : 'Sign In',
                                ),
                        ),
                        if (authState.requiresTwoFactorAuth) ...[
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              ref.read(authProvider.notifier).logout();
                              _twoFactorController.clear();
                            },
                            child: const Text('Back to login'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
