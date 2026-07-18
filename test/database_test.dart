import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(testExecutor()));
  tearDown(() => db.close());

  TracksCompanion track(String path, {String title = 't', String artist = 'a'}) =>
      TracksCompanion.insert(
        path: path,
        fingerprint: 'fp-$path',
        title: title,
        artist: Value(artist),
        sizeBytes: 100,
        mtimeMs: 1,
      );

  test('upsert 按 path 幂等：同 path 二次写入是更新不是新增', () async {
    await db.upsertTrack(track('/m/a.mp3', title: 'old'));
    await db.upsertTrack(track('/m/a.mp3', title: 'new'));
    final all = await db.watchTracks('').first;
    expect(all.length, 1);
    expect(all.single.title, 'new');
  });

  test('watchTracks 空查询返回全部并按 title 排序', () async {
    await db.upsertTrack(track('/m/b.mp3', title: 'Beta'));
    await db.upsertTrack(track('/m/a.mp3', title: 'Alpha'));
    final all = await db.watchTracks('').first;
    expect(all.map((t) => t.title).toList(), ['Alpha', 'Beta']);
  });

  test('watchTracks 排序大小写不敏感：apple < Banana < Zebra', () async {
    await db.upsertTrack(track('/m/1.mp3', title: 'apple'));
    await db.upsertTrack(track('/m/2.mp3', title: 'Zebra'));
    await db.upsertTrack(track('/m/3.mp3', title: 'Banana'));
    final all = await db.watchTracks('').first;
    expect(all.map((t) => t.title).toList(), ['apple', 'Banana', 'Zebra']);
  });

  test('re-upsert 不变量：id 与 addedAt 保持首次插入值（承重语义，防回退）', () async {
    // 显式给首行一个远在过去的 addedAt——若 update 路径错误地重写 addedAt
    //（如改回 insertOnConflictUpdate 或全列 DoUpdate），对比必然失败。
    await db.upsertTrack(track('/m/a.mp3', title: 'old')
        .copyWith(addedAt: Value(DateTime.utc(2020, 1, 1))));
    final first = (await db.watchTracks('').first).single;
    await db.upsertTrack(track('/m/a.mp3', title: 'new'));
    final second = (await db.watchTracks('').first).single;
    expect(second.title, 'new');
    expect(second.id, first.id);
    expect(second.addedAt, first.addedAt);
  });

  test('watchTracks 按标题/歌手模糊匹配', () async {
    await db.upsertTrack(track('/m/a.mp3', title: '晴天', artist: '周杰伦'));
    await db.upsertTrack(track('/m/b.mp3', title: 'Yellow', artist: 'Coldplay'));
    expect((await db.watchTracks('周杰').first).length, 1);
    expect((await db.watchTracks('yellow').first).length, 1);
    expect((await db.watchTracks('不存在').first), isEmpty);
  });

  test('pathIndex 返回 path→(mtimeMs,sizeBytes) 映射', () async {
    await db.upsertTrack(track('/m/a.mp3'));
    final idx = await db.pathIndex();
    expect(idx['/m/a.mp3'], (mtimeMs: 1, sizeBytes: 100));
  });

  test('deleteTracksNotIn 删除不在给定集合中的行（分块安全）', () async {
    for (var i = 0; i < 600; i++) {
      await db.upsertTrack(track('/m/$i.mp3'));
    }
    await db.deleteTracksNotIn({for (var i = 0; i < 10; i++) '/m/$i.mp3'});
    expect((await db.watchTracks('').first).length, 10);
  });

  test('batchUpsertTracks：单批 300 行（100 冲突更新 + 200 新插入），id/addedAt 不变', () async {
    final t0 = DateTime.utc(2020, 1, 1);
    for (var i = 0; i < 100; i++) {
      await db.upsertTrack(
          track('/m/$i.mp3', title: 'old-$i').copyWith(addedAt: Value(t0)));
    }
    final before = {
      for (final t in await db.watchTracks('').first)
        t.path: (id: t.id, addedAt: t.addedAt),
    };

    await db.batchUpsertTracks([
      for (var i = 0; i < 300; i++) track('/m/$i.mp3', title: 'new-$i'),
    ]);

    final after = await db.watchTracks('').first;
    expect(after.length, 300);
    final byPath = {for (final t in after) t.path: t};
    for (var i = 0; i < 300; i++) {
      expect(byPath['/m/$i.mp3']!.title, 'new-$i', reason: '内容已更新: /m/$i.mp3');
    }
    for (var i = 0; i < 100; i++) {
      final p = '/m/$i.mp3';
      expect(byPath[p]!.id, before[p]!.id, reason: 'id 不变: $p');
      expect(byPath[p]!.addedAt, before[p]!.addedAt, reason: 'addedAt 不变: $p');
    }
  });

  test('scan roots 增删查', () async {
    await db.addScanRoot('/music');
    await db.addScanRoot('/music'); // 幂等
    expect(await db.watchScanRoots().first, ['/music']);
    await db.removeScanRoot('/music');
    expect(await db.watchScanRoots().first, isEmpty);
  });
}
