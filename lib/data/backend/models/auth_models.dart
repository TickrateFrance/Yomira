/// Backend auth DTOs.
class AuthUser {
  AuthUser({required this.id, required this.username});

  final String id;
  final String username;

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      AuthUser(id: json['id'] as String, username: json['username'] as String);
}

class AuthResult {
  AuthResult({required this.token, required this.user});

  final String token;
  final AuthUser user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        token: json['token'] as String,
        user: AuthUser.fromJson((json['user'] as Map).cast<String, dynamic>()),
      );
}
