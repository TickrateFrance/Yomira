import 'package:dio/dio.dart';

import '../app_update.dart';
import '../config.dart';

/// Injects X-App-Version + X-Platform on every backend call, and escalates to a
/// force-update on any 426 Upgrade Required response.
class VersionInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-App-Version'] = AppConfig.appVersion;
    options.headers['X-Platform'] = AppConfig.platform;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 426) {
      final data = err.response?.data;
      final url = (data is Map && data['url'] is String) ? data['url'] as String : '';
      signalForceUpdate(url);
    }
    handler.next(err);
  }
}
