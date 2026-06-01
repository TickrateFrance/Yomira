import 'package:dio/dio.dart';

import '../config.dart';
import 'retry_interceptor.dart';
import 'version_interceptor.dart';

/// Builds the Dio instances the app uses (Suwayomi content + sync backend).
class DioClient {
  DioClient._();

  /// Suwayomi-Server Dio (GraphQL). Long receive timeout because Suwayomi
  /// scrapes sources live on first fetch. [baseUrl] points at the server root.
  /// [authHeader] is the "Basic …" value when the server has Basic Auth on.
  static Dio buildSuwayomi(String baseUrl, {String? authHeader}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Content-Type': 'application/json',
          if (authHeader != null) 'Authorization': authHeader,
        },
      ),
    );
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
