import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../widgets/auth_form_field.dart';

/// Signup page for new user registration.
///
/// Collects email, password, and name for account creation.
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    final authService = context.read<AuthService>();
    final success = await authService.signup(
      email: _emailController.text,
      password: _passwordController.text,
      name: _nameController.text,
    );

    if (success && mounted) {
      context.go('/home');
    }
  }

  void _navigateToLogin() {
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AuthFormField(
              controller: _nameController,
              label: 'Name',
            ),
            const SizedBox(height: 16),
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
            ElevatedButton(
              onPressed: _handleSignup,
              child: const Text('Sign Up'),
            ),
            TextButton(
              onPressed: _navigateToLogin,
              child: const Text('Already have an account? Login'),
            ),
          ],
        ),
      ),
    );
  }
}
