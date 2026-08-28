import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

/// 同一首歌存在于两个路径下 = 两行同指纹(`tracks.path` 唯一,`fingerprint` 不唯一)。
///
/// 这不是异常情况:母 spec §7.5 明说「宁可留重复,不可丢歌」,而 M3-C 的同名避让
/// (`xxx (2).mp3`)正会制造内容相同的第二份。按指纹取曲目的查询必须能容忍重复,
/// 否则 `/v1/file/{fp}` 端点会抛异常 → 500 → 对端从此再也拉不到这首歌。
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(testExecutor()));
  tearDown(() => db.close());

  Future<void> addTrack(String path, String fp) => db.upsertTrack(
    TracksCompanion.insert(
      path: path,
      fingerprint: fp,
      title: '及时雨',
      sizeBytes: 1,
      mtimeMs: 1,
    ),
  );

  test('同指纹两行时 trackByFingerprint 返回其中一行,不抛异常', () async {
    await addTrack('/m/及时雨.mp3', 'fp-dup');
    await addTrack('/m/及时雨 (2).mp3', 'fp-dup'); // 同名避让产生的副本

    final t = await db.trackByFingerprint('fp-dup');
    expect(t, isNotNull);
    expect(t!.fingerprint, 'fp-dup');
    expect(
      ['/m/及时雨.mp3', '/m/及时雨 (2).mp3'],
      contains(t.path), // 哪一行都行,重要的是不炸
    );
  });

  test('指纹不存在时仍返回 null', () async {
    expect(await db.trackByFingerprint('没有这个指纹'), isNull);
  });
}
