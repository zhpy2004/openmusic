import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:sqlite3/sqlite3.dart' as sq;

import 'helpers/db.dart';

void main() {
  test('新建库:可读写设置项,缺省返回 null', () async {
    final db = AppDatabase(testExecutor());
    addTearDown(db.close);

    expect(await db.getSetting('locale'), isNull);
    await db.setSetting('locale', 'en');
    expect(await db.getSetting('locale'), 'en');
    await db.setSetting('locale', 'zh');
    expect(await db.getSetting('locale'), 'zh'); // 覆盖写
  });

  test('v3 旧库升级到 v4:app_settings 表被建出且可用,原有数据不丢', () async {
    // 手工构造一个 schemaVersion=3 的库(测试只走 onCreate,不覆盖 onUpgrade,
    // 所以必须这样实证——M2-A 迁移时定下的规矩)。
    // v3 时 v2(歌单/收藏/播放记录)与 v3(文本修正)引入的表都该已存在——
    // 过去只到 v4/v5 时这些表从没被后续迁移碰过,缺了也不显形;v6 第一次
    // 对它们 ADD COLUMN,缺表会直接报 "no such table"(sync_migration_v6_test
    // 与 sync_migration_test 已经踩过同款坑),所以这里要补全,且用 v6 之前
    // (未加软删列)的原始形态,不能抄现在的 database.dart 定义。
    final native = sq.sqlite3.openInMemory();
    native.execute('''
      CREATE TABLE scan_roots (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE);
      CREATE TABLE tracks (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE, fingerprint TEXT NOT NULL,
        title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL,
        album_artist TEXT NOT NULL, duration_ms INTEGER NOT NULL,
        track_number INTEGER, year INTEGER, size_bytes INTEGER NOT NULL,
        mtime_ms INTEGER NOT NULL, added_at INTEGER NOT NULL);
      CREATE TABLE playlists (
        uuid TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE playlist_items (
        playlist_uuid TEXT NOT NULL, track_fp TEXT NOT NULL,
        position INTEGER NOT NULL, UNIQUE (playlist_uuid, track_fp));
      CREATE TABLE favorites (
        track_fp TEXT NOT NULL PRIMARY KEY, added_at INTEGER NOT NULL);
      CREATE TABLE play_events (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, track_fp TEXT NOT NULL,
        played_at INTEGER NOT NULL, event_type TEXT NOT NULL DEFAULT 'played');
      CREATE TABLE track_overrides (
        track_fp TEXT NOT NULL PRIMARY KEY, title TEXT, artist TEXT,
        album TEXT, updated_at INTEGER NOT NULL);
      INSERT INTO scan_roots (path) VALUES ('/music');
      PRAGMA user_version = 3;
    ''');

    final db = AppDatabase(NativeDatabase.opened(native));
    addTearDown(db.close);

    // 触发迁移
    await db.setSetting('locale', 'en');
    expect(await db.getSetting('locale'), 'en');
    // 旧数据仍在
    expect(await db.watchScanRoots().first, ['/music']);
  });
}
