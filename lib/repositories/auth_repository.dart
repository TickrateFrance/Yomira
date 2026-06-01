import 'package:dio/dio.dart';

import '../data/backend/backend_api.dart';
import '../data/backend/models/auth_models.dart';
import '../data/backend/token_store.dart';

/// Auth state + operations. Holds the current user when logged in.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final BackendApi _api;
  final TokenStore _tokens;

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Restore session from stored JWT. Returns true if still valid.
  Future<bool> tryRestore() async {
    final token = await _tokens.read();
    if (token == null) return false;
    try {
      _currentUser = await _api.me();
      return true;
    } on DioException {
      // Expired/invalid — clear it.
      await _tokens.clear();
      _currentUser = null;
      return false;
    }
  }

  Future<AuthUser> register(String username, String password) async {
    final result = await _api.register(username, password);
    await _tokens.write(result.token);
    _currentUser = result.user;
    return result.user;
  }

  Future<AuthUser> login(String username, String password) async {
    final result = await _api.login(username, password);
    await _tokens.write(result.token);
    _currentUser = result.user;
    return result.user;
  }

  Future<void> logout() async {
    await _tokens.clear();
    _currentUser = null;
  }
}

/// Maps Dio errors to user-facing messages.
String describeBackendError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final serverMsg = (error.response?.data is Map)
        ? (error.response!.data['error'] as String?)
        : null;
    if (serverMsg != null) return serverMsg;
    if (status == 401) return 'Invalid credentials';
    if (status == 409) return 'Username already taken';
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Cannot reach server. Check the backend URL.';
      case DioExceptionType.receiveTimeout:
        return 'Server timed out.';
      default:
        return 'Network error.';
    }
  }
  return 'Unexpected error.';
}
