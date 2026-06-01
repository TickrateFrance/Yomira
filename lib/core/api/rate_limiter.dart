import 'dart:async';
import 'dart:collection';

/// Sliding-window rate limiter. Tracks timestamps of recent permits and
/// delays new ones until under the cap. Acquisition is serialized so
/// concurrent callers queue fairly instead of racing the window check.
class RateLimiter {
  RateLimiter._({required int max, required this.window}) : _max = max;

  factory RateLimiter.perSecond(int permits) =>
      RateLimiter._(max: permits, window: const Duration(seconds: 1));

  factory RateLimiter.perMinute(int permits) =>
      RateLimiter._(max: permits, window: const Duration(minutes: 1));

  final int _max;
  final Duration window;

  final Queue<DateTime> _timestamps = Queue<DateTime>();
  Future<void> _chain = Future.value();

  /// Awaits until a permit is available, then records its timestamp.
  Future<void> acquire() {
    final completer = Completer<void>();
    _chain = _chain.then((_) async {
      await _waitForSlot();
      _timestamps.addLast(DateTime.now());
      completer.complete();
    });
    return completer.future;
  }

  Future<void> _waitForSlot() async {
    while (true) {
      final now = DateTime.now();
      while (_timestamps.isNotEmpty && now.difference(_timestamps.first) >= window) {
        _timestamps.removeFirst();
      }
      if (_timestamps.length < _max) return;
      final wait = window - now.difference(_timestamps.first);
      await Future<void>.delayed(wait + const Duration(milliseconds: 5));
    }
  }
}
