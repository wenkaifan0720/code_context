import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/services/auth_service.dart';

/// Settings page for app configuration.
///
/// Provides access to profile, preferences, and logout.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            subtitle: const Text('View and edit your profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/profile'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            subtitle: const Text('Configure notification preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Navigate to notifications settings
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Privacy'),
            subtitle: const Text('Privacy and security settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Navigate to privacy settings
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final authService = context.read<AuthService>();
              await authService.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
    );
  }
}
