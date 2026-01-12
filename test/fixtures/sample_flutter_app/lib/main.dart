import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/pages/login_page.dart';
import 'features/auth/pages/signup_page.dart';
import 'features/home/pages/home_page.dart';
import 'features/products/pages/product_detail_page.dart';
import 'features/products/pages/product_list_page.dart';
import 'features/settings/pages/profile_page.dart';
import 'features/settings/pages/settings_page.dart';

void main() {
  runApp(const MyApp());
}

/// Main application widget.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sample App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

/// Application router configuration using go_router.
final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupPage(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: '/products',
      builder: (context, state) => const ProductListPage(),
    ),
    GoRoute(
      path: '/products/:id',
      builder: (context, state) => ProductDetailPage(
        productId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfilePage(),
    ),
  ],
);
