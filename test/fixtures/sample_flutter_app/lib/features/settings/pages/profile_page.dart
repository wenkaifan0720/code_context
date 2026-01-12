import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/services/auth_service.dart';

/// Profile page displaying user information.
///
/// Shows user avatar, name, email, and edit options.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
      ),
      body: Consumer<AuthService>(
        builder: (context, auth, _) {
          final user = auth.currentUser;
          if (user == null) {
            return const Center(child: Text('Not logged in'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: user.avatarUrl != null
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: user.avatarUrl == null
                      ? Text(
                          user.name.isNotEmpty
                              ? user.name[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 32),
                        )
                      : null,
                ),
                const SizedBox(height: 24),
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      // TODO: Edit profile
                    },
                    child: const Text('Edit Profile'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
