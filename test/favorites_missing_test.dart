import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/ui/favorites_screen.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';
import 'helpers/pump.dart';

/// 回归:同步过来的收藏,指向的曲目在本机往往还不存在(元数据先到、文件要等
/// M3-C 才搬)。收藏页早先把这类曲目**直接丢弃**,于是同步过来的红心整个
/// "人间蒸发",用户看到的现象就是"收藏同步不了"。现在改成与歌单详情页一致:
/// 置灰保留、显示「文件缺失」、不可点播。
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(testExecutor());
    // 本机只有 fp-local 这一首;fp-remote 是同步过来的收藏,本机没有文件。
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/local.mp3',
        fingerprint: 'fp-local',
        title: '本机有的歌',
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
    await db.toggleFavorite('fp-local');
    await db.toggleFavorite('fp-remote');
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          audioEngineProvider.overrideWithValue(FakeAudioEngine()),
        ],
        child: localizedApp(const FavoritesScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('本机缺文件的收藏仍然显示,标为「文件缺失」且不可点播', (tester) async {
    await pumpScreen(tester);

    expect(find.text('本机有的歌'), findsOneWidget);
    expect(find.text('文件缺失'), findsOneWidget); // 不再被丢弃

    final missingTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('文件缺失'), matching: find.byType(ListTile)),
    );
    expect(missingTile.onTap, isNull); // 点不动
    expect(missingTile.enabled, isFalse);

    final presentTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('本机有的歌'), matching: find.byType(ListTile)),
    );
    expect(presentTile.onTap, isNotNull); // 本机有的照常可播
  });
}
