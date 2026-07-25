import 'dart:async';

/// 串行化的最小间隔限流器。MusicBrainz 要求 ≤1 req/秒,超了会被封。
/// 必须串行化:并发调用者若各自只读"上次时间",会同时判定可放行而一起冲出去。
class RateLimiter {
  RateLimiter(this.minInterval);

  final Duration minInterval;

  Future<void> _tail = Future<void>.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// 排到队尾,轮到自己时若距上次放行不足 minInterval 则补齐等待。
  Future<void> acquire() {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return prev.then((_) async {
      final wait = minInterval - DateTime.now().difference(_last);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      _last = DateTime.now();
      done.complete();
    });
  }
}
