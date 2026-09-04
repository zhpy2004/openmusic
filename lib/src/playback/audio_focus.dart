import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'playback_controller.dart';

/// Android 音频焦点管理(DB-1)。audio_service 与 media_kit 都不管理音频焦点
/// (前者官方文档明确交给 audio_session;后者 Dart 层无相关代码)——此前整条
/// 播放链路没有任何一方显式持有焦点,通知栏触发的 resume 在这个空白下表现为
/// PlayerBase 被系统以 IPlayer::stop() 收回。见 deferred-bugs.md DB-1。
Future<void> initAudioFocus(PlaybackController controller) async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // 开始播放时主动声明持有焦点;暂停/停止不主动 abandon——与应用内
  // 暂停后仍可能被通知栏/蓝牙键恢复的场景一致,过早交出焦点反而添乱。
  controller.engine.playingStream.listen((playing) {
    if (playing) unawaited(session.setActive(true));
  });

  session.interruptionEventStream.listen((event) {
    if (!event.begin) return; // 焦点归还:不自动续播,用户可能是被来电打断
    switch (event.type) {
      case AudioInterruptionType.pause:
      case AudioInterruptionType.unknown:
        controller.engine.pause();
      case AudioInterruptionType.duck:
        // mpv 音量降低不在本次修复范围内,直接放行。
        break;
    }
  });
}
