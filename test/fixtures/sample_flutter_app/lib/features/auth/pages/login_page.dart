import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../widgets/auth_form_field.dart';

/// Login page for user authentication.
///
/// Displays email/password form and navigates to home on success.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final authService = context.read<AuthService>();
    final success = await authService.login(
      _emailController.text,
      _passwordController.text,
    );

    if (success && mounted) {
      context.go('/home');
    }
  }

  void _navigateToSignup() {
    context.go('/signup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AuthFormField(
              controller: _emailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            AuthFormField(
              controller: _passwordController,
              label: 'Password',
              obscureText: true,
            ),
            const SizedBox(height: 24),
            Consumer<AuthService>(
              builder: (context, auth, _) {
                if (auth.error != null) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      auth.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            ElevatedButton(
              onPressed: _handleLogin,
              child: const Text('Login'),
            ),
            TextButton(
              onPressed: _navigateToSignup,
              child: const Text("Don't have an account? Sign up"),
            ),
          ],
        ),
      ),
    );
  }
}
