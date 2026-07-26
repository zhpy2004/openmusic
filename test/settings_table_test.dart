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
