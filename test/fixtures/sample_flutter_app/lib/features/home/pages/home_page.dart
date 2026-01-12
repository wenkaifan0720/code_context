import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/services/auth_service.dart';

/// Main home page displayed after login.
///
/// Shows welcome message and navigation to other features.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: Consumer<AuthService>(
        builder: (context, auth, _) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${auth.currentUser?.name ?? 'Guest'}!',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                _NavigationCard(
                  title: 'Products',
                  subtitle: 'Browse our catalog',
                  icon: Icons.shopping_bag,
                  onTap: () => context.go('/products'),
                ),
                const SizedBox(height: 16),
                _NavigationCard(
                  title: 'Profile',
                  subtitle: 'View your profile',
                  icon: Icons.person,
                  onTap: () => context.go('/profile'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  const _NavigationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
