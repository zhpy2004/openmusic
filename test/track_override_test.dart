import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(testExecutor()));
  tearDown(() => db.close());

  test('schemaVersion 为 4', () {
    expect(db.schemaVersion, 4);
  });

  test('覆盖表与既有表并存:插曲目 + 插覆盖各自可查', () async {
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/a.mp3',
        fingerprint: 'fpA',
        title: '原标题',
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
    await db
        .into(db.trackOverrides)
        .insert(
          TrackOverridesCompanion.insert(
            trackFp: 'fpA',
            title: const Value('新标题'),
            updatedAt: 100,
          ),
        );
    expect((await db.select(db.tracks).get()).single.title, '原标题');
    expect((await db.select(db.trackOverrides).get()).single.title, '新标题');
  });

  Future<void> insTrack(String path, String fp, String title) => db.upsertTrack(
    TracksCompanion.insert(
      path: path,
      fingerprint: fp,
      title: title,
      artist: const Value('原歌手'),
      album: const Value('原专辑'),
      sizeBytes: 1,
      mtimeMs: 1,
    ),
  );

  test('setTrackOverride 写覆盖并物化回 tracks', () async {
    await insTrack('/m/a.mp3', 'fpA', '原标题');
    await db.setTrackOverride('fpA', title: '晴天', artist: '周杰伦');
    final t = (await db.select(db.tracks).get()).single;
    expect(t.title, '晴天');
    expect(t.artist, '周杰伦');
    expect(t.album, '原专辑'); // 未覆盖的字段保持原值
    final o = await db.getTrackOverride('fpA');
    expect(o!.title, '晴天');
    expect(o.album, isNull);
  });

  test('setTrackOverride 二次调用覆盖前值且不重复插入', () async {
    await insTrack('/m/a.mp3', 'fpA', '原标题');
    await db.setTrackOverride('fpA', title: '第一次');
    await db.setTrackOverride('fpA', title: '第二次');
    expect((await db.select(db.trackOverrides).get()).length, 1);
    expect((await db.select(db.tracks).get()).single.title, '第二次');
  });

  test('clearTrackOverride 删除覆盖行', () async {
    await insTrack('/m/a.mp3', 'fpA', '原标题');
    await db.setTrackOverride('fpA', title: '晴天');
    await db.clearTrackOverride('fpA');
    expect(await db.getTrackOverride('fpA'), isNull);
  });

  test('applyFileTags 把文件标签写回 tracks(撤销时用)', () async {
    await insTrack('/m/a.mp3', 'fpA', '原标题');
    await db.setTrackOverride('fpA', title: '晴天');
    await db.clearTrackOverride('fpA');
    await db.applyFileTags('fpA', title: '原标题', artist: '原歌手', album: '原专辑');
    expect((await db.select(db.tracks).get()).single.title, '原标题');
  });

  test('reapplyAllOverrides 在重扫覆写后恢复修正', () async {
    await insTrack('/m/a.mp3', 'fpA', '原标题');
    await db.setTrackOverride('fpA', title: '晴天');
    // 模拟重扫:按 path upsert 写回文件原始标签,盖掉修正
    await insTrack('/m/a.mp3', 'fpA', '原标题');
    expect((await db.select(db.tracks).get()).single.title, '原标题');
    await db.reapplyAllOverrides();
    expect((await db.select(db.tracks).get()).single.title, '晴天');
  });

  test('setTrackOverride 合并语义:省略的字段保留原有修正', () async {
    await insTrack('/m/a.mp3', 'fpA', '原标题');
    await db.setTrackOverride('fpA', title: 'T1', artist: 'A1');
    await db.setTrackOverride('fpA', title: 'T2'); // 只改标题
    final o = await db.getTrackOverride('fpA');
    expect(o!.title, 'T2');
    expect(o.artist, 'A1'); // 保留,不被 null 抹掉
    final t = (await db.select(db.tracks).get()).single;
    expect(t.title, 'T2');
    expect(t.artist, 'A1');
    // 关键:重扫后再叠加,显示不应发生漂移
    await insTrack('/m/a.mp3', 'fpA', '原标题'); // 模拟重扫覆写
    await db.reapplyAllOverrides();
    final t2 = (await db.select(db.tracks).get()).single;
    expect(t2.title, 'T2');
    expect(t2.artist, 'A1');
  });

  test('给尚未扫描到的指纹写覆盖:不报错,tracks 无行被改', () async {
    await db.setTrackOverride('ghost', title: 'X');
    expect((await db.getTrackOverride('ghost'))!.title, 'X');
    expect(await db.select(db.tracks).get(), isEmpty);
  });
}
