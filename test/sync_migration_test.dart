import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

/// 造一个 v4 形态的库(删掉 v5 的两张表、再用 [degradeSchemaToV5] 把 v6 加过
/// 软删列的老表也退化掉、user_version 退回 4),关闭后用当前 AppDatabase
/// 重新打开触发 onUpgrade。
///
/// 这样"从新版退化"而不是手写 CREATE TABLE,可以绕开 i18n 迁移测试踩过的坑:
/// 手写旧表结构漏一列(如 scan_roots.id 自增)会让 drift map 时 null check 崩。
/// 老表也必须一并退化,否则 v6 迁移一旦碰到某张现存表就会因为"列已存在/
/// 表未退化"而炸——这正是 v6 加软删列时踩出来的教训。
void main() {
  late File file;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('om-mig');
    file = File('${dir.path}/openmusic.sqlite');
  });

  tearDown(() async {
    if (await file.exists()) await file.delete();
  });

  test('v4→v5 迁移:建两张新表,旧数据无损', () async {
    // 1. 建库并退化成 v4
    final v4 = AppDatabase(testFileExecutor(file.path));
    // v6 加过软删列的老表也要退化,否则 onUpgrade 走到 v5→v6 那段时会因为
    // 列已存在 / 表未退化而报错(sync_migration_v6_test 踩过的同类坑)。
    await degradeSchemaToV5(v4);
    await v4.customStatement('DROP TABLE IF EXISTS local_device');
    await v4.customStatement('DROP TABLE IF EXISTS peers');
    await v4.customStatement(
      "INSERT INTO tracks (path, fingerprint, title, artist, album, "
      "album_artist, duration_ms, size_bytes, mtime_ms) "
      "VALUES ('/m/a.mp3', 'fp-a', '老歌', '歌手', '', '', 0, 1, 1)",
    );
    await v4.customStatement('PRAGMA user_version = 4');
    await v4.close();

    // 2. 重新打开 —— 走 onUpgrade(4 → 5)
    final db = AppDatabase(testFileExecutor(file.path));
    expect(await db.getLocalDevice(), isNull); // 新表建成,内容为空
    expect(await db.watchPeers().first, isEmpty);

    final tracks = await db.watchTracks('').first;
    expect(tracks.single.title, '老歌'); // 旧数据一字未动

    await db.ensureLocalDevice(deviceId: 'x', deviceName: 'n');
    expect((await db.getLocalDevice())!.deviceId, 'x');
    await db.close();
  });
}
