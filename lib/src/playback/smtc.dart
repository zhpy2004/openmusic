import 'package:smtc_windows/smtc_windows.dart';

import 'playback_controller.dart';

/// Windows 系统媒体传输控制（SMTC）：媒体悬浮窗 + 键盘媒体键（spec §3.2）。
Future<void> initSmtc(PlaybackController controller) async {
  await SMTCWindows.initialize();
  final smtc = SMTCWindows(
    config: const SMTCConfig(
      playEnabled: true,
      pauseEnabled: true,
      nextEnabled: true,
      prevEnabled: true,
      stopEnabled: false,
      fastForwardEnabled: false,
      rewindEnabled: false,
    ),
  );

  smtc.buttonPressStream.listen((button) {
    switch (button) {
      case PressedButton.play:
        controller.engine.play();
      case PressedButton.pause:
        controller.engine.pause();
      case PressedButton.next:
        controller.engine.next();
      case PressedButton.previous:
        controller.engine.previous();
      default:
        break;
    }
  });

  controller.addListener(() {
    final t = controller.currentTrack;
    if (t != null) {
      smtc.updateMetadata(
        MusicMetadata(title: t.title, artist: t.artist, album: t.album),
      );
    }
  });
  controller.engine.playingStream.listen((playing) {
    smtc.setPlaybackStatus(
      playing ? PlaybackStatus.playing : PlaybackStatus.paused,
    );
  });
}
