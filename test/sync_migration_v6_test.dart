import 'dart:io';

// Variable 来自 drift,`database.dart` 不会把它 re-export —— 少这行编译不过。
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

/// 造 v5 形态的库(删掉 v6 的列与索引 + user_version 退回 5),关闭后重新打开
/// 触发 onUpgrade。"从新版退化"而不是手写 CREATE TABLE —— i18n 那次手写漏列
/// 导致 drift map 时 null check 崩过。
///
/// SQLite 不支持 DROP COLUMN(3.35 之前),这里用重建表的方式造旧结构。
void main() {
  late File file;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('om-mig-v6');
    file = File('${dir.path}/openmusic.sqlite');
  });

  tearDown(() async {
    if (await file.exists()) await file.delete();
  });

  Future<void> degradeToV5(AppDatabase db) async {
    await degradeSchemaToV5(db);
    await db.customStatement('PRAGMA user_version = 5');
  }

  /// 走一遍最基本的读写链路,证明"补列"(v3/v4/v5→v6)与"建表"(v1/v2→v6)
  /// 两条迁移路径产出的结构是等价的、真能用——不只是"打得开"。
  Future<void> assertBasicFlowWorks(AppDatabase db) async {
    expect(db.schemaVersion, 7);

    final uuid = await db.createPlaylist('新歌单');
    await db.addToPlaylist(uuid, 'fp-a');
    await db.removeFromPlaylist(uuid, 'fp-a');
    expect(await db.watchPlaylistItems(uuid).first, isEmpty);

    await db.toggleFavorite('fp-a'); // 收藏
    await db.toggleFavorite('fp-a'); // 取消
    expect(await db.isFavorite('fp-a'), isFalse);
  }

  test('v5→v6:加列、回填 updatedAt、去重后建唯一索引,旧数据无损', () async {
    final v5 = AppDatabase(testFileExecutor(file.path));
    // 先用 v6 的 API 造数据,再退化结构
    final uuid = await v5.createPlaylist('开车');
    await v5.customStatement(
      "INSERT INTO tracks (path, fingerprint, title, artist, album, album_artist, "
      "duration_ms, size_bytes, mtime_ms) "
      "VALUES ('/m/a.mp3', 'fp-a', '老歌', '歌手', '', '', 0, 1, 1)",
    );
    await v5.addToPlaylist(uuid, 'fp-a');
    await v5.customStatement(
      "INSERT INTO favorites (track_fp, added_at, updated_at, deleted) "
      "VALUES ('fp-a', 1700000000000, 1700000000000, 0)",
    );
    // **先删索引再插重复行**:这个实例是全新打开的,已经走过 onCreate 建好了
    // 唯一索引;不先删掉,下面第二条重复插入会当场撞 UNIQUE 约束,根本走不到
    // degradeToV5()。删掉正是在模拟"v5 时代还没有这个索引"。
    await v5.customStatement('DROP INDEX IF EXISTS idx_play_events_natural_key');
    // 故意插两条完全相同的播放记录(v5 允许,v6 要去重)
    await v5.customStatement(
      "INSERT INTO play_events (track_fp, played_at, event_type) VALUES ('fp-a', 111, 'played')",
    );
    await v5.customStatement(
      "INSERT INTO play_events (track_fp, played_at, event_type) VALUES ('fp-a', 111, 'played')",
    );
    await degradeToV5(v5);
    await v5.close();

    // 重新打开 → 走 onUpgrade(5 → 6)
    final db = AppDatabase(testFileExecutor(file.path));

    // 旧数据无损
    final playlists = await db.watchPlaylists().first;
    expect(playlists.single.name, '开车');
    expect(playlists.single.deleted, isFalse);

    // updatedAt 回填:favorites 用 addedAt
    final favRows = await db.customSelect(
      'SELECT updated_at FROM favorites WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).get();
    expect(favRows.single.read<int>('updated_at'), 1700000000000);

    // updatedAt 回填:playlist_items 用所属歌单的 updatedAt,且不为 0
    final itemRows = await db.customSelect(
      'SELECT updated_at FROM playlist_items',
    ).get();
    expect(itemRows.single.read<int>('updated_at'), greaterThan(0));

    // play_events 去重成功
    final events = await db.customSelect('SELECT COUNT(*) c FROM play_events').get();
    expect(events.single.read<int>('c'), 1);

    // 唯一索引真的生效:再插同键一条应被忽略
    await db.logPlayEventAt('fp-a', 111);
    final after = await db.customSelect('SELECT COUNT(*) c FROM play_events').get();
    expect(after.single.read<int>('c'), 1);

    await db.close();
  });

  test('v2→v6 跳级升级:track_overrides 走"建表"、其余四表走"补列",两条路径都不撞列', () async {
    final v2 = AppDatabase(testFileExecutor(file.path));
    await v2.customStatement(
      "INSERT INTO tracks (path, fingerprint, title, artist, album, album_artist, "
      "duration_ms, size_bytes, mtime_ms) "
      "VALUES ('/m/a.mp3', 'fp-a', '老歌', '歌手', '', '', 0, 1, 1)",
    );
    // v5 形状对 playlists/playlist_items/favorites/track_overrides 这四张表
    // 而言就等于 v2 形状——v2 到 v5 之间没人动过它们。
    await degradeSchemaToV5(v2);
    // track_overrides 是 v2→v3(M2-B)才引入的,真正的 v2 库里压根没有这张表;
    // app_settings/local_device/peers 更晚,也一并去掉,才是完整的 v2 形态。
    await v2.customStatement('DROP TABLE track_overrides');
    await v2.customStatement('DROP TABLE IF EXISTS app_settings');
    await v2.customStatement('DROP TABLE IF EXISTS local_device');
    await v2.customStatement('DROP TABLE IF EXISTS peers');
    await v2.customStatement('PRAGMA user_version = 2');
    await v2.close();

    // 重新打开 → 走 onUpgrade(2 → 6):track_overrides 由 from<3 的
    // m.createTable 建出(自带 v6 形状),其余四表由 from<6 里 from>=2 的
    // addColumn 补列——如果两条路径有一条撞了 duplicate column,这里就会崩。
    final db = AppDatabase(testFileExecutor(file.path));

    final tracks = await db.watchTracks('').first;
    expect(tracks.single.title, '老歌'); // v1 时代就有的数据无损

    await assertBasicFlowWorks(db);
    await db.close();
  });

  test('v1→v6 跳级升级:四张 M2-A 表全部由 onCreate 时代的 createTable 补出,不撞列', () async {
    final v1 = AppDatabase(testFileExecutor(file.path));
    await v1.customStatement(
      "INSERT INTO tracks (path, fingerprint, title, artist, album, album_artist, "
      "duration_ms, size_bytes, mtime_ms) "
      "VALUES ('/m/a.mp3', 'fp-a', '老歌', '歌手', '', '', 0, 1, 1)",
    );
    // v1 只有 tracks/scan_roots,其余表(M2-A 起才引入)全部去掉。
    await v1.customStatement('DROP INDEX IF EXISTS idx_play_events_natural_key');
    await v1.customStatement('DROP TABLE playlists');
    await v1.customStatement('DROP TABLE playlist_items');
    await v1.customStatement('DROP TABLE favorites');
    await v1.customStatement('DROP TABLE play_events');
    await v1.customStatement('DROP TABLE track_overrides');
    await v1.customStatement('DROP TABLE IF EXISTS app_settings');
    await v1.customStatement('DROP TABLE IF EXISTS local_device');
    await v1.customStatement('DROP TABLE IF EXISTS peers');
    await v1.customStatement('PRAGMA user_version = 1');
    await v1.close();

    // 重新打开 → 走 onUpgrade(1 → 6):四张表全部由 from<2/from<3 的
    // m.createTable 建出(自带 v6 形状),from<6 里的 addColumn 因
    // from>=2/from>=3 都为假而不会执行——不这样处理就会撞 duplicate column。
    final db = AppDatabase(testFileExecutor(file.path));

    final tracks = await db.watchTracks('').first;
    expect(tracks.single.title, '老歌'); // v1 时代就有的数据无损

    await assertBasicFlowWorks(db);
    await db.close();
  });
}
