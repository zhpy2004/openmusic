import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/ui/now_playing_screen.dart';

import 'helpers/db.dart';
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
  testWidgets('中途打开正在播放页：未收到任何 duration/position 流事件时，仍显示引擎当前快照的总时长与已播放时长', (
    tester,
  ) async {
    final engine = FakeAudioEngine();
    engine.duration = const Duration(minutes: 3, seconds: 25);
    engine.position = const Duration(seconds: 42);

    final db = AppDatabase(testExecutor());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [
        audioEngineProvider.overrideWithValue(engine),
        databaseProvider.overrideWithValue(db), // 红心按钮读 isFavoriteProvider
      ],
    );
    addTearDown(container.dispose);

    // 通过同一个 container 拿到 widget 将要读取的那个 PlaybackController 实例，
    // 让它在“打开正在播放页”之前就已经在播放——模拟中途打开页面的场景。
    final controller = container.read(playbackControllerProvider);
    await controller.playTracks([track(1, '/a', 'A')], startIndex: 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NowPlayingScreen()),
      ),
    );

    // 不 pump 任何 duration/position 流事件——只 pump 一帧建立 StreamBuilder,
    // 复现"broadcast 流对晚订阅者不回放"的场景。
    await tester.pump();

    expect(find.text('3:25'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
  });
}
