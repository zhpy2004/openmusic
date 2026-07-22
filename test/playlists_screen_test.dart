import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/ui/playlist_detail_screen.dart';
import 'package:openmusic/src/ui/playlists_screen.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeAudioEngine engine;
  setUp(() {
    db = AppDatabase(testExecutor());
    engine = FakeAudioEngine();
  });
  tearDown(() => db.close());

  Widget app() => ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: PlaylistsScreen()),
  );

  testWidgets('置顶「我喜欢的」+ 列出歌单', (tester) async {
    await db.createPlaylist('晨间');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('我喜欢的'), findsOneWidget);
    expect(find.text('晨间'), findsOneWidget);
  });

  testWidgets('新建歌单', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '夜跑');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(find.text('夜跑'), findsOneWidget);
  });

  testWidgets('详情:展示曲目、缺失置灰、移除', (tester) async {
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/a.mp3',
        fingerprint: 'fpA',
        title: 'Alpha',
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
    final u = await db.createPlaylist('L');
    await db.addToPlaylist(u, 'fpA');
    await db.addToPlaylist(u, 'ghost'); // 缺失

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(engine), // 详情页底部迷你播放栏需要
        ],
        child: MaterialApp(
          home: PlaylistDetailScreen(uuid: u, name: 'L'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('文件缺失'), findsOneWidget); // 缺失项占位文案

    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('删歌单需二次确认', (tester) async {
    final u = await db.createPlaylist('待删');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(engine), // 详情页底部迷你播放栏需要
        ],
        child: MaterialApp(
          home: PlaylistDetailScreen(uuid: u, name: '待删'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('删除歌单「待删」?'), findsOneWidget); // 确认对话框
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 用 runAsync 跑真实事件循环:drift 的 .watch() 首值经 Timer 投递,
    // testWidgets 的 fake-async 时钟在 pumpAndSettle 后冻结,直接 await 流会
    // 永远等不到该 timer(且 --timeout 也是 fake timer,无法救场)→ 真挂死。
    final remaining = await tester.runAsync(() => db.watchPlaylists().first);
    expect(remaining, isEmpty);
  });
}
