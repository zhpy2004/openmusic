import 'package:audio_service/audio_service.dart';

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
      if (t == null) return;
      mediaItem.add(
        MediaItem(
          id: t.path,
          title: t.title,
          artist: t.artist,
          album: t.album,
          duration: Duration(milliseconds: t.durationMs),
        ),
      );
    });
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
