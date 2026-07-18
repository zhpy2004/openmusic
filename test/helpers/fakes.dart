import 'dart:async';

import 'package:openmusic/src/library/tag_reader.dart';
import 'package:openmusic/src/playback/audio_engine.dart';

/// 标题 = 文件名；path 含 "corrupt" 时抛异常，模拟损坏文件。
class FakeTagReader implements TagReader {
  final List<String> readPaths = [];

  @override
  Future<TrackMetadata> read(String path) async {
    readPaths.add(path);
    if (path.contains('corrupt')) throw Exception('bad file');
    return TrackMetadata(title: path.split(RegExp(r'[\\/]')).last);
  }
}

class FakeAudioEngine implements AudioEngine {
  final calls = <String>[];
  List<String> queue = [];
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration;
  final indexCtrl = StreamController<int>.broadcast();
  final playingCtrl = StreamController<bool>.broadcast();
  final positionCtrl = StreamController<Duration>.broadcast();
  final durationCtrl = StreamController<Duration?>.broadcast();

  @override
  Future<void> setQueue(
    List<String> paths, {
    int startIndex = 0,
    bool play = true,
  }) async {
    queue = paths;
    calls.add('setQueue(${paths.length}, start:$startIndex, play:$play)');
    indexCtrl.add(startIndex);
    playingCtrl.add(play);
  }

  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> next() async => calls.add('next');
  @override
  Future<void> previous() async => calls.add('previous');
  @override
  Future<void> jump(int index) async => calls.add('jump($index)');
  @override
  Future<void> seek(Duration position) async => calls.add('seek($position)');
  @override
  Future<void> setShuffle(bool enabled) async => calls.add('shuffle($enabled)');
  @override
  Future<void> setRepeatMode(RepeatMode mode) async =>
      calls.add('repeat($mode)');

  @override
  Stream<int> get indexStream => indexCtrl.stream;
  @override
  Stream<bool> get playingStream => playingCtrl.stream;
  @override
  Stream<Duration> get positionStream => positionCtrl.stream;
  @override
  Stream<Duration?> get durationStream => durationCtrl.stream;

  @override
  Future<void> dispose() async {
    await indexCtrl.close();
    await playingCtrl.close();
    await positionCtrl.close();
    await durationCtrl.close();
  }
}
