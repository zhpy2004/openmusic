import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../data/database.dart';
import '../library/cover_art.dart';
import 'audio_engine.dart';
import 'playback_controller.dart';

/// 把 PlaybackController/AudioEngine 的状态桥接到 Android 媒体会话：
/// 通知栏、锁屏、蓝牙按键（spec §3.2）。
class OpenmusicAudioHandler extends BaseAudioHandler with SeekHandler {
  OpenmusicAudioHandler(this._controller) {
    _bind();
  }

  final PlaybackController _controller;
  AudioEngine get _engine => _controller.engine;

  void _bind() {
    _engine.playingStream.listen((playing) {
      playbackState.add(
        playbackState.value.copyWith(
          playing: playing,
          processingState: AudioProcessingState.ready,
          controls: [
            MediaControl.skipToPrevious,
            playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {MediaAction.seek},
        ),
      );
    });
    _engine.positionStream.listen((pos) {
      playbackState.add(playbackState.value.copyWith(updatePosition: pos));
    });
    _controller.addListener(() {
      final t = _controller.currentTrack;
      if (t == null || t.path == _publishedPath) return;
      _publishedPath = t.path;
      // 封面要摸盘,而 addListener 是同步回调 —— 先不带图发一版让通知立刻更新,
      // 图查到了再补发一版。best-effort:查不到就维持无图那版。
      mediaItem.add(_itemFor(t));
      unawaited(_publishWithArt(t));
    });
  }

  /// 已发布到媒体会话的曲目路径。PlaybackController 的 notifyListeners 在
  /// 播放/暂停/进度等变化时也会触发,没有这个去重就会每次都去摸一遍盘。
  String? _publishedPath;

  MediaItem _itemFor(Track t, {Uri? artUri}) => MediaItem(
    id: t.path,
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: Duration(milliseconds: t.durationMs),
    artUri: artUri,
  );

  Future<void> _publishWithArt(Track t) async {
    final cover = await resolveCoverPath(t.path);
    if (cover == null) return;
    // 期间可能已经切歌了,别把旧封面盖到新曲目上。
    if (_publishedPath != t.path) return;
    mediaItem.add(_itemFor(t, artUri: Uri.file(cover)));
  }

  @override
  Future<void> play() => _engine.play();
  @override
  Future<void> pause() => _engine.pause();
  @override
  Future<void> skipToNext() => _engine.next();
  @override
  Future<void> skipToPrevious() => _engine.previous();
  @override
  Future<void> seek(Duration position) => _engine.seek(position);
  @override
  Future<void> stop() => _engine.pause();
}
