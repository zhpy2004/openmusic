import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/ui/library_screen.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';
import 'helpers/pump.dart';

void main() {
  late AppDatabase db;
  late FakeAudioEngine engine;

  setUp(() async {
    db = AppDatabase(testExecutor());
    engine = FakeAudioEngine();
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/a.mp3',
        fingerprint: 'fp1',
        title: 'Alpha',
        artist: const Value('Artist A'),
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/b.mp3',
        fingerprint: 'fp2',
        title: 'Beta',
        artist: const Value('Artist B'),
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
  });
  tearDown(() => db.close());

  Widget app() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioEngineProvider.overrideWithValue(engine),
    ],
    child: localizedApp(const LibraryScreen()),
  );

  testWidgets('列表展示曲目标题与歌手', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Artist B'), findsOneWidget);
  });

  testWidgets('点击曲目 → 引擎收到整队列并从该曲开始', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    expect(engine.calls, contains('setQueue(2, start:1, play:true)'));
  });

  testWidgets('搜索过滤列表', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Alp');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);
  });

  // 真机实测(1 万曲目首扫中途)发现:搜了没结果却提示「曲库为空——到设置里添加
  // 文件夹并扫描」,会让人误以为库坏了。无匹配与真空库必须是两种文案。
  testWidgets('搜索无匹配 → 提示「没有匹配的曲目」,而不是曲库为空', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'zzz不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的曲目'), findsOneWidget);
    expect(find.textContaining('曲库为空'), findsNothing);
  });

  testWidgets('曲库真的为空(没搜索)→ 仍提示添加文件夹', (tester) async {
    await db.customStatement('DELETE FROM tracks');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.textContaining('曲库为空'), findsOneWidget);
    expect(find.text('没有匹配的曲目'), findsNothing);
  });

  testWidgets('曲目 ⋮ 菜单可加入歌单', (tester) async {
    await db.createPlaylist('L1');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入歌单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('L1'));
    await tester.pumpAndSettle();
    // 断言写入:L1 有 1 首(用 runAsync 跑真实事件循环读 drift 流)。
    final u = (await tester.runAsync(
      () => db.watchPlaylists().first,
    ))!.single.uuid;
    final items = await tester.runAsync(() => db.watchPlaylistItems(u).first);
    expect(items!.length, 1);
  });

  testWidgets('曲目 ⋮ 菜单有「刮削」项', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    expect(find.text('刮削'), findsOneWidget);
  });

  testWidgets('红心按钮切换收藏', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // 初始未收藏:两曲各一个空心。点第一首的红心 → 该曲入收藏。
    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pumpAndSettle();
    final favs = await tester.runAsync(() => db.watchFavorites().first);
    expect(favs, ['fp1']);
    expect(find.byIcon(Icons.favorite), findsOneWidget); // 变实心
  });
}
