import 'dart:async';
import 'package:dio/dio.dart';

/// Retries transient failures with exponential backoff.
/// Handles 429 (respects Retry-After), 503, and network/timeout errors.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
  });

  final Dio dio;
  final int maxRetries;
  final Duration baseDelay;

  static const _retryCountKey = 'retry_count';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_retryCountKey] as int?) ?? 0;

    if (!_shouldRetry(err) || attempt >= maxRetries) {
      return handler.next(err);
    }

    final delay = _delayFor(err, attempt);
    await Future<void>.delayed(delay);

    final options = err.requestOptions;
    options.extra = {...options.extra, _retryCountKey: attempt + 1};

    try {
      final response = await dio.fetch(options);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _shouldRetry(DioException err) {
    final status = err.response?.statusCode;
    if (status == 429 || status == 503) return true;
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        return false;
    }
  }

  Duration _delayFor(DioException err, int attempt) {
    // Honor Retry-After (seconds) on 429 if present.
    final retryAfter = err.response?.headers.value('retry-after');
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      if (seconds != null) return Duration(seconds: seconds);
    }
    // Exponential backoff: base * 2^attempt.
    return baseDelay * (1 << attempt);
  }
}
