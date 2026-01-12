import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../repositories/auth_repository.dart';

/// Service layer for authentication business logic.
///
/// Manages user sessions and provides authentication state
/// to the rest of the application.
class AuthService extends ChangeNotifier {
  AuthService(this._authRepository);

  final AuthRepository _authRepository;

  User? _currentUser;
  bool _isLoading = false;
  String? _error;

  /// Currently authenticated user, or null if not logged in.
  User? get currentUser => _currentUser;

  /// Whether an auth operation is in progress.
  bool get isLoading => _isLoading;

  /// Whether the user is currently logged in.
  bool get isLoggedIn => _currentUser != null;

  /// Error message from the last failed operation.
  String? get error => _error;

  /// Attempt to log in with the provided credentials.
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentUser = await _authRepository.login(email, password);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Create a new user account.
  Future<bool> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentUser = await _authRepository.signup(
        email: email,
        password: password,
        name: name,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Log out the current user.
  Future<void> logout() async {
    await _authRepository.logout();
    _currentUser = null;
    notifyListeners();
  }

  /// Initialize by checking for existing session.
  Future<void> initialize() async {
    _currentUser = await _authRepository.getCurrentUser();
    notifyListeners();
  }
}
