import '../../../core/api_client.dart';
import '../models/user.dart';

/// Repository for authentication operations.
///
/// Handles user login, signup, and session management.
class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  /// Authenticate a user with email and password.
  ///
  /// Returns the authenticated [User] on success.
  /// Throws [AuthException] if credentials are invalid.
  Future<User> login(String email, String password) async {
    final response = await _apiClient.post('/auth/login', {
      'email': email,
      'password': password,
    });
    return User.fromJson(response);
  }

  /// Register a new user account.
  ///
  /// Returns the created [User] on success.
  Future<User> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _apiClient.post('/auth/signup', {
      'email': email,
      'password': password,
      'name': name,
    });
    return User.fromJson(response);
  }

  /// Log out the current user.
  Future<void> logout() async {
    await _apiClient.post('/auth/logout', {});
  }

  /// Get the currently authenticated user.
  Future<User?> getCurrentUser() async {
    try {
      final response = await _apiClient.get('/auth/me');
      return User.fromJson(response);
    } catch (_) {
      return null;
    }
  }
}
