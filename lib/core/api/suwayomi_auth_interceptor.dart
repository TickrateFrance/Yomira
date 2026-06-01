import 'package:dio/dio.dart';

import '../../data/backend/token_store.dart';

/// Attaches the user's JWT (Bearer) to Suwayomi requests. The backend/Caddy
/// validates it and injects the real Suwayomi credentials server-side, so the
/// app never ships the Suwayomi password.
class SuwayomiAuthInterceptor extends Interceptor {
  SuwayomiAuthInterceptor(this._tokens);

  final TokenStore _tokens;

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = _tokens.cachedToken ?? await _tokens.read();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
