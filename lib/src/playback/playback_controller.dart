import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import 'audio_engine.dart';

/// 应用层播放状态：持有队列（Track 列表）与模式，播放动作全部代理给 AudioEngine。
/// 引擎负责"怎么放"（gapless/shuffle 顺序），这里负责"放什么、现在是哪首"。
class PlaybackController extends ChangeNotifier {
  PlaybackController(this._engine) {
    _indexSub = _engine.indexStream.listen((i) {
      _index = i;
      notifyListeners();
    });
    _playingSub = _engine.playingStream.listen((p) {
      _playing = p;
      notifyListeners();
    });
  }

  final AudioEngine _engine;
  late final StreamSubscription<int> _indexSub;
  late final StreamSubscription<bool> _playingSub;

  List<Track> _queue = [];
  int _index = 0;
  bool _playing = false;
  bool _shuffle = false;
  RepeatMode _repeatMode = RepeatMode.off;

  List<Track> get queue => List.unmodifiable(_queue);
  bool get playing => _playing;
  bool get shuffle => _shuffle;
  RepeatMode get repeatMode => _repeatMode;
  AudioEngine get engine => _engine;

  Track? get currentTrack =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    _queue = List.of(tracks);
    _index = startIndex;
    await _engine.setQueue(
      tracks.map((t) => t.path).toList(),
      startIndex: startIndex,
    );
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    await _engine.setShuffle(_shuffle);
    notifyListeners();
  }

  Future<void> cycleRepeatMode() async {
    _repeatMode = switch (_repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    await _engine.setRepeatMode(_repeatMode);
    notifyListeners();
  }

  @override
  void dispose() {
    _indexSub.cancel();
    _playingSub.cancel();
    super.dispose();
  }
}
