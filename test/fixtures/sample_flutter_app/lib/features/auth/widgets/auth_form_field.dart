import 'package:flutter/material.dart';

/// Reusable form field for authentication forms.
class AuthFormField extends StatelessWidget {
  const AuthFormField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
