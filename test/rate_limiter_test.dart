import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/scraper/rate_limiter.dart';

void main() {
  test('连续 acquire 之间至少间隔 minInterval', () async {
    final rl = RateLimiter(const Duration(milliseconds: 50));
    final sw = Stopwatch()..start();
    await rl.acquire();
    await rl.acquire();
    await rl.acquire();
    sw.stop();
    // 3 次 = 2 个间隔;留裕度防调度抖动导致偶发失败
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(90));
  });

  test('并发 acquire 被串行化,不会同时放行', () async {
    final rl = RateLimiter(const Duration(milliseconds: 50));
    final sw = Stopwatch()..start();
    await Future.wait([rl.acquire(), rl.acquire(), rl.acquire()]);
    sw.stop();
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(90));
  });
}
