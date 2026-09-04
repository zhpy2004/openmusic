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

  test('每次切曲触发 onTrackStarted(含起播,精确序列)', () async {
    final started = <String>[];
    controller.onTrackStarted = (track) => started.add(track.fingerprint);
    await controller.playTracks(tracks, startIndex: 0);
    engine.indexCtrl.add(1);
    await pumpEventQueue();
    engine.indexCtrl.add(2);
    await pumpEventQueue();
    // 起播 fp1 + 切到 fp2、fp3,各一次,不多不少。
    expect(started, ['fp1', 'fp2', 'fp3']);
  });

  test('新队列复用同一下标不会被 distinct 吞掉起播埋点(H1 回归)', () async {
    final started = <String>[];
    controller.onTrackStarted = (track) => started.add(track.fingerprint);
    // 单曲队列 A,下标 0。
    await controller.playTracks([track(1, '/a', 'A')], startIndex: 0);
    await pumpEventQueue();
    // 换单曲队列 B,同样下标 0——真实引擎 indexStream.distinct() 会吞掉这次
    // index 事件,若埋点只挂在 index 监听上,B 的起播就丢了。
    await controller.playTracks([track(2, '/b', 'B')], startIndex: 0);
    await pumpEventQueue();
    expect(started, ['fp1', 'fp2']);
  });

  test('重复播放同一首(再次点播)仍计一次起播', () async {
    final started = <String>[];
    controller.onTrackStarted = (track) => started.add(track.fingerprint);
    await controller.playTracks([track(1, '/a', 'A')], startIndex: 0);
    await pumpEventQueue();
    await controller.playTracks([track(1, '/a', 'A')], startIndex: 0);
    await pumpEventQueue();
    expect(started, ['fp1', 'fp1']); // 显式再次点播算新的一次
  });

  group('queueFinished(SMTC 用于区分"播完停下"与"用户暂停",T10)', () {
    test('空队列时为 false', () {
      expect(controller.queueFinished, isFalse);
    });

    test('非末曲暂停时为 false(还没放完,只是停在半路)', () async {
      await controller.playTracks(tracks, startIndex: 0);
      await pumpEventQueue();
      engine.playingCtrl.add(false);
      await pumpEventQueue();
      expect(controller.currentTrack?.title, 'A'); // 不是末曲
      expect(controller.queueFinished, isFalse);
    });

    test('末曲仍在播放时为 false', () async {
      await controller.playTracks(tracks, startIndex: 2);
      await pumpEventQueue();
      expect(controller.playing, isTrue);
      expect(controller.queueFinished, isFalse);
    });

    test('RepeatMode.off 下放到末曲且停止播放时为 true', () async {
      await controller.playTracks(tracks, startIndex: 2);
      await pumpEventQueue();
      engine.playingCtrl.add(false); // 引擎报告放完停止
      await pumpEventQueue();
      expect(controller.queueFinished, isTrue);
    });

    test('RepeatMode.all/one 下即便停在末曲也不算"播完"(会继续循环)', () async {
      await controller.cycleRepeatMode(); // off -> all
      await controller.playTracks(tracks, startIndex: 2);
      await pumpEventQueue();
      engine.playingCtrl.add(false);
      await pumpEventQueue();
      expect(controller.queueFinished, isFalse);
    });
  });
}
