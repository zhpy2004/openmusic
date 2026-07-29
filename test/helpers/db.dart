import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:sqlite3/open.dart';

bool _overridden = false;

/// 测试用内存数据库。Windows 上从 tool/sqlite3/ 加载 sqlite3.dll。
///
/// closeStreamsSynchronously：drift 默认在最后一个订阅者取消后用 Timer.run
/// 延迟一轮事件循环再清理流缓存；widget test（FakeAsync）里该 timer 会触发
/// "A Timer is still pending" 断言，且 tearDown 的 db.close() 会永远等待
/// 这个不被推进的假 timer（drift 源码注释即为此场景推荐本选项）。
QueryExecutor testExecutor() {
  if (Platform.isWindows && !_overridden) {
    _overridden = true;
    // 相对路径：假设 CWD 为包根（flutter test 默认从包根运行）。
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('tool/sqlite3/sqlite3.dll'),
    );
  }
  return DatabaseConnection(
    NativeDatabase.memory(),
    closeStreamsSynchronously: true,
  );
}

/// 文件型测试库:迁移测试需要"关掉再重新打开同一个库",内存库做不到
/// (关掉即销毁)。与 testExecutor 共用同一份 sqlite3.dll 覆盖逻辑。
QueryExecutor testFileExecutor(String path) {
  if (Platform.isWindows && !_overridden) {
    _overridden = true;
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('tool/sqlite3/sqlite3.dll'),
    );
  }
  return DatabaseConnection(
    NativeDatabase(File(path)),
    closeStreamsSynchronously: true,
  );
}

/// 把当前(v6)schema 的四张表就地重建成 v5 形态(去掉 M3-B 加的软删列),
/// 并删掉 v6 的唯一索引。迁移测试用它模拟旧库。
///
/// **抽成共享的原因**:三个迁移测试各抄一份的话,下次迁移只要碰到老表,
/// 就要同时修三处 —— 本次 v6 正是这么炸出来的。
///
/// 只管这四张表与索引;调用方自己负责额外的降级(如 v4→v5 测试还要
/// DROP local_device/peers)与最终的 `PRAGMA user_version = ...`。
Future<void> degradeSchemaToV5(AppDatabase db) async {
  await db.customStatement('DROP INDEX IF EXISTS idx_play_events_natural_key');
  // playlists:去掉 deleted
  await db.customStatement(
    'CREATE TABLE playlists_v5 (uuid TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, '
    'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
  );
  await db.customStatement(
    'INSERT INTO playlists_v5 SELECT uuid, name, created_at, updated_at FROM playlists',
  );
  await db.customStatement('DROP TABLE playlists');
  await db.customStatement('ALTER TABLE playlists_v5 RENAME TO playlists');
  // playlist_items:去掉 updated_at / deleted
  await db.customStatement(
    'CREATE TABLE playlist_items_v5 (playlist_uuid TEXT NOT NULL, track_fp TEXT NOT NULL, '
    'position INTEGER NOT NULL, UNIQUE (playlist_uuid, track_fp))',
  );
  await db.customStatement(
    'INSERT INTO playlist_items_v5 SELECT playlist_uuid, track_fp, position FROM playlist_items',
  );
  await db.customStatement('DROP TABLE playlist_items');
  await db.customStatement('ALTER TABLE playlist_items_v5 RENAME TO playlist_items');
  // favorites:去掉 updated_at / deleted
  await db.customStatement(
    'CREATE TABLE favorites_v5 (track_fp TEXT NOT NULL PRIMARY KEY, added_at INTEGER NOT NULL)',
  );
  await db.customStatement(
    'INSERT INTO favorites_v5 SELECT track_fp, added_at FROM favorites',
  );
  await db.customStatement('DROP TABLE favorites');
  await db.customStatement('ALTER TABLE favorites_v5 RENAME TO favorites');
  // track_overrides:去掉 deleted
  await db.customStatement(
    'CREATE TABLE track_overrides_v5 (track_fp TEXT NOT NULL PRIMARY KEY, title TEXT, '
    'artist TEXT, album TEXT, updated_at INTEGER NOT NULL)',
  );
  await db.customStatement(
    'INSERT INTO track_overrides_v5 SELECT track_fp, title, artist, album, updated_at FROM track_overrides',
  );
  await db.customStatement('DROP TABLE track_overrides');
  await db.customStatement('ALTER TABLE track_overrides_v5 RENAME TO track_overrides');
}
