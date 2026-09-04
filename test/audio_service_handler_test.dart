import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/playback/audio_service_handler.dart';
import 'package:openmusic/src/playback/playback_controller.dart';

import 'helpers/fakes.dart';

Track _track(String path, String title) => Track(
  id: 1,
  path: path,
  fingerprint: 'fp-$path',
  title: title,
  artist: '',
  album: '',
  albumArtist: '',
  durationMs: 0,
  trackNumber: null,
  year: null,
  sizeBytes: 1,
  mtimeMs: 1,
  addedAt: DateTime(2026),
);

void main() {
  test('position 流高频 tick 不应逐次触发 playbackState 广播', () async {
    final engine = FakeAudioEngine();
    final controller = PlaybackController(engine);
    final handler = OpenmusicAudioHandler(controller);

    final emissions = <Duration?>[];
    final sub = handler.playbackState.listen((s) => emissions.add(s.updatePosition));

    await controller.playTracks([_track('/a', 'A')], startIndex: 0);
    emissions.clear(); // 只看 playTracks 之后、position tick 期间的广播次数

    for (var i = 0; i < 50; i++) {
      engine.positionCtrl.add(Duration(milliseconds: i * 20)); // 模拟 50 次高频 tick
    }
    await Future<void>.delayed(Duration.zero);

    // 精确上界:实测 50 次 tick(0ms..980ms,20ms 间隔)在 800ms 阈值下只应
    // 产生 3 次广播——1 次是 playTracks 里 play() 异步落地触发的 playingStream
    // 广播(位置仍是初始的 0),1 次是 distinct 对第一个原始 tick(0ms)必然放行,
    // 最后 1 次是累计位置跨过 800ms 阈值时(980ms 跨度 / 800ms 阈值,只够跨一次)。
    // 用 lessThanOrEqualTo(3) 而不是 lessThan(50),这样节流间隔被意外改小
    // (比如变成每隔一个 tick 或 100ms 阈值)时测试才会真的失败。
    expect(
      emissions.length,
      lessThanOrEqualTo(3),
      reason: '50 次 position tick 在 800ms 节流阈值下最多应产生 3 次广播',
    );

    await sub.cancel();
  });
}
