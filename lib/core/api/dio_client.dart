import 'package:dio/dio.dart';

import '../../data/backend/token_store.dart';
import '../config.dart';
import 'retry_interceptor.dart';
import 'suwayomi_auth_interceptor.dart';
import 'version_interceptor.dart';

/// Builds the Dio instances the app uses (Suwayomi content + sync backend).
class DioClient {
  DioClient._();

  /// Suwayomi-Server Dio (GraphQL). Long receive timeout because Suwayomi
  /// scrapes sources live on first fetch. [baseUrl] points at the server root.
  /// Auth is the user's JWT (Bearer), injected per-request from [tokenStore];
  /// the server validates it and adds the real Suwayomi credentials.
  static Dio buildSuwayomi(String baseUrl, {TokenStore? tokenStore}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
        },
      ),
    );
    if (tokenStore != null) {
      dio.interceptors.add(SuwayomiAuthInterceptor(tokenStore));
    }
    dio.interceptors.add(RetryInterceptor(dio: dio));
    return dio;
  }

  /// Backend Dio. [baseUrl] is resolved at runtime (see RuntimeConfig), so the
  /// URL can change without rebuilding the app.
  static Dio buildBackend(String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    dio.interceptors.add(VersionInterceptor());
    dio.interceptors.add(RetryInterceptor(dio: dio));
    return dio;
  }
}
