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
      // 队列内切曲(自动续播/next/prev):指纹变了才算一次新起播。
      // 起播那一下由 playTracks 显式发,这里靠指纹去重避免 setQueue 回声重复计。
      final t = currentTrack;
      if (t != null && t.fingerprint != _lastStartedFp) _fireTrackStarted(t);
    });
    _playingSub = _engine.playingStream.listen((p) {
      _playing = p;
      notifyListeners();
    });
  }

  /// 切到某曲开始播放时回调(main 里接 db.logPlayEvent)。逐曲计数,
  /// 含队列自动切下一首;不是"每次点播放列表"一条。
  void Function(Track track)? onTrackStarted;

  /// 上一次已发出起播回调的指纹,用于给 index 监听去重(真实引擎 indexStream
  /// 以 .distinct() 收尾,同下标再入队会被吞——所以起播必须由 playTracks 显式发)。
  String? _lastStartedFp;

  void _fireTrackStarted(Track t) {
    _lastStartedFp = t.fingerprint;
    onTrackStarted?.call(t);
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

  /// 队列是否已"播完停下"(非循环、放到末曲且未在播放)。
  /// 用途:SMTC 侧要把"播完自然停"和"用户主动暂停"区分开——两者在
  /// PlaybackStatus.playing/paused 二态下文案相同(见 smtc.dart)。
  ///
  /// 是启发式信号,非精确的"本曲播放完成"事件(AudioEngine 未暴露该事件,
  /// media_kit 虽有 completed 流,但引入需扩展引擎接口,超出本次改动范围)。
  /// 已知两处误差,均只影响 SMTC 悬浮窗文案、不影响实际播放/按键:
  /// - 用户在末曲手动暂停(还没放完)也会判定为"已播完";
  /// - 起播单曲队列的一瞬间(index 先到位、playingStream 的 true 事件后到)
  ///   会有 <100ms 的误判窗口,playingStream 触发后立刻纠正。
  bool get queueFinished =>
      !_playing &&
      _repeatMode == RepeatMode.off &&
      _queue.isNotEmpty &&
      _index == _queue.length - 1;

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0}) async {
    _queue = List.of(tracks);
    _index = startIndex;
    // 显式起播:在 await 之前无条件发(再次点播同一首也算新的一次)。放在 await 前
    // 是为了先坐实 _lastStartedFp——setQueue 随后引发的 index 回声(同指纹)会被
    // 监听里的去重挡掉,不会重复计。放到 await 后则回声可能抢先到达而重复。
    final t = currentTrack;
    if (t != null) _fireTrackStarted(t);
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
