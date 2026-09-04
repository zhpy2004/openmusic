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

    expect(
      emissions.length,
      lessThan(50),
      reason: '50 次 position tick 不该产生 50 次 playbackState 广播',
    );

    await sub.cancel();
  });
}
