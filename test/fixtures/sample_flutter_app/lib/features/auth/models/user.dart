/// User model representing an authenticated user.
class User {
  const User({
    required this.id,
    required this.email,
    required this.name,
    this.avatarUrl,
  });

  /// Unique user identifier.
  final String id;

  /// User's email address.
  final String email;

  /// User's display name.
  final String name;

  /// Optional avatar URL.
  final String? avatarUrl;

  /// Create a User from JSON data.
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  /// Convert to JSON representation.
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };
}
