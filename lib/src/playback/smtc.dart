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
    // 队列自然放完(非循环、末曲播毕)时报 stopped 而不是 paused,
    // 与用户主动暂停区分开(见 PlaybackController.queueFinished 的启发式与已知局限)。
    // stopped 不依赖 SMTCConfig.stopEnabled(该配置只管 Stop 按钮是否显示)。
    smtc.setPlaybackStatus(
      playing
          ? PlaybackStatus.playing
          : (controller.queueFinished
                ? PlaybackStatus.stopped
                : PlaybackStatus.paused),
    );
  });
}
