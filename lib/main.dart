import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app/app.dart';
import 'src/app/providers.dart';
import 'src/data/database.dart';
import 'src/playback/audio_service_handler.dart';
import 'src/playback/media_kit_engine.dart';
import 'src/playback/playback_controller.dart';
import 'src/playback/smtc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final database = AppDatabase(driftDatabase(name: 'openmusic'));
  final engine = MediaKitEngine();

  // --- 平台集成初始化占位：Task 10 (audio_service)、Task 11 (SMTC) 在此追加 ---

  // PlaybackController 需要在 AudioService.init 之前创建，
  // 因此不再由 provider 构造，改为注入现成实例。
  final controller = PlaybackController(engine);
  // 逐曲播放埋点(play_events 追加日志;历史 UI 后期做)。best-effort:关库/满盘
  // 等写入异常吞掉,不让未观测的异步错误冒泡(埋点失败不该影响播放)。
  controller.onTrackStarted = (track) => unawaited(
    database.logPlayEvent(track.fingerprint).catchError((Object _) {}),
  );

  if (Platform.isAndroid) {
    try {
      await AudioService.init(
        builder: () => OpenmusicAudioHandler(controller),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.openmusic.channel.audio',
          androidNotificationChannelName: 'OpenMusic',
          androidNotificationOngoing: true,
        ),
      );
    } catch (e) {
      // 媒体会话初始化失败只损失通知栏/锁屏/蓝牙控制,应用本体照常运行。
      debugPrint('AudioService.init failed, running without media session: $e');
    }
  }

  if (Platform.isWindows) {
    try {
      await initSmtc(controller);
    } catch (e) {
      // SMTC 初始化失败只损失悬浮窗/媒体键,应用本体照常运行。
      debugPrint('initSmtc failed, running without SMTC: $e');
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        audioEngineProvider.overrideWithValue(engine),
        playbackControllerProvider.overrideWith((ref) => controller),
      ],
      child: const OpenMusicApp(),
    ),
  );
}
