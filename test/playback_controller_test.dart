import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/playback/audio_engine.dart';
import 'package:openmusic/src/playback/playback_controller.dart';

import 'helpers/fakes.dart';

Track track(int id, String path, String title) => Track(
  id: id,
  path: path,
  fingerprint: 'fp$id',
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
  late FakeAudioEngine engine;
  late PlaybackController controller;

  setUp(() {
    engine = FakeAudioEngine();
    controller = PlaybackController(engine);
  });
  tearDown(() => controller.dispose());

  final tracks = [
    track(1, '/a', 'A'),
    track(2, '/b', 'B'),
    track(3, '/c', 'C'),
  ];

  test('playTracks 把路径队列交给引擎并从指定下标播放', () async {
    await controller.playTracks(tracks, startIndex: 1);
    expect(engine.calls, contains('setQueue(3, start:1, play:true)'));
    expect(engine.queue, ['/a', '/b', '/c']);
  });

  test('currentTrack 跟随引擎 indexStream', () async {
    await controller.playTracks(tracks, startIndex: 0);
    engine.indexCtrl.add(2);
    await pumpEventQueue();
    expect(controller.currentTrack?.title, 'C');
  });

  test('引擎给出越界 index 时 currentTrack 为 null 而不是崩溃', () async {
    await controller.playTracks(tracks, startIndex: 0);
    engine.indexCtrl.add(99);
    await pumpEventQueue();
    expect(controller.currentTrack, isNull);
  });

  test('toggleShuffle 翻转状态并下发引擎', () async {
    await controller.toggleShuffle();
    expect(controller.shuffle, isTrue);
    expect(engine.calls, contains('shuffle(true)'));
    await controller.toggleShuffle();
    expect(controller.shuffle, isFalse);
  });

  test('playing 跟随引擎 playingStream', () async {
    await controller.playTracks(tracks, startIndex: 0);
    await pumpEventQueue();
    expect(controller.playing, isTrue); // setQueue 的 play:true 事件已送达
    engine.playingCtrl.add(false);
    await pumpEventQueue();
    expect(controller.playing, isFalse);
  });

  test('cycleRepeatMode: off → all → one → off', () async {
    expect(controller.repeatMode, RepeatMode.off);
    await controller.cycleRepeatMode();
    expect(controller.repeatMode, RepeatMode.all);
    await controller.cycleRepeatMode();
    expect(controller.repeatMode, RepeatMode.one);
    await controller.cycleRepeatMode();
    expect(controller.repeatMode, RepeatMode.off);
    expect(engine.calls.where((c) => c.startsWith('repeat(')).toList(), [
      'repeat(RepeatMode.all)',
      'repeat(RepeatMode.one)',
      'repeat(RepeatMode.off)',
    ]);
  });
}
