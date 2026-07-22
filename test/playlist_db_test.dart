import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

Future<void> _insTrack(AppDatabase db, String path, String fp, String title) =>
    db.upsertTrack(
      TracksCompanion.insert(
        path: path,
        fingerprint: fp,
        title: title,
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(testExecutor()));
  tearDown(() => db.close());

  test('schemaVersion 为 2', () {
    expect(db.schemaVersion, 2);
  });

  test('新表与旧表并存:插曲目 + 插歌单各自可查', () async {
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '/m/a.mp3',
        fingerprint: 'fp1',
        title: 'A',
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );
    await db
        .into(db.playlists)
        .insert(
          PlaylistsCompanion.insert(
            uuid: 'u1',
            name: '测试歌单',
            createdAt: 100,
            updatedAt: 100,
          ),
        );
    expect((await db.select(db.tracks).get()).length, 1);
    expect((await db.select(db.playlists).get()).single.name, '测试歌单');
  });

  test('createPlaylist 生成 uuid、watchPlaylists 按 updatedAt 倒序', () async {
    final u1 = await db.createPlaylist('晨间');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final u2 = await db.createPlaylist('夜跑');
    expect(u1, isNot(u2));
    final list = await db.watchPlaylists().first;
    expect(list.map((p) => p.name), ['夜跑', '晨间']); // 新建在前
  });

  test('renamePlaylist 改名并更新 updatedAt', () async {
    final u = await db.createPlaylist('旧名');
    final before = (await db.watchPlaylists().first).single.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await db.renamePlaylist(u, '新名');
    final after = (await db.watchPlaylists().first).single;
    expect(after.name, '新名');
    expect(after.updatedAt, greaterThan(before));
  });

  test('deletePlaylist 删除歌单', () async {
    final u = await db.createPlaylist('待删');
    await db.deletePlaylist(u);
    expect(await db.watchPlaylists().first, isEmpty);
  });

  test('createPlaylist 紧循环无重复 uuid(碰撞压力)', () async {
    final ids = <String>{};
    for (var i = 0; i < 1000; i++) {
      ids.add(await db.createPlaylist('p$i'));
    }
    expect(ids.length, 1000); // 全唯一
  });

  test('addToPlaylist 追加去重 + watchPlaylistItems 关联曲目', () async {
    await _insTrack(db, '/m/a.mp3', 'fpA', 'Alpha');
    await _insTrack(db, '/m/b.mp3', 'fpB', 'Beta');
    final u = await db.createPlaylist('L');
    await db.addToPlaylist(u, 'fpA');
    await db.addToPlaylist(u, 'fpB');
    await db.addToPlaylist(u, 'fpA'); // 重复:忽略
    final items = await db.watchPlaylistItems(u).first;
    expect(items.map((i) => i.track?.title), ['Alpha', 'Beta']);
  });

  test('重复 addToPlaylist 不改 updatedAt(no-op)', () async {
    final u = await db.createPlaylist('L');
    await db.addToPlaylist(u, 'fpA');
    final before = (await db.watchPlaylists().first).single.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await db.addToPlaylist(u, 'fpA'); // 重复
    final after = (await db.watchPlaylists().first).single.updatedAt;
    expect(after, before); // 未 bump
  });

  test('缺失曲目:指纹在但 tracks 无对应行 → item 保留, track 为 null', () async {
    final u = await db.createPlaylist('L');
    await db.addToPlaylist(u, 'ghost');
    final items = await db.watchPlaylistItems(u).first;
    expect(items.single.fp, 'ghost');
    expect(items.single.track, isNull);
  });

  test('removeFromPlaylist 移除单曲', () async {
    await _insTrack(db, '/m/a.mp3', 'fpA', 'Alpha');
    final u = await db.createPlaylist('L');
    await db.addToPlaylist(u, 'fpA');
    await db.removeFromPlaylist(u, 'fpA');
    expect(await db.watchPlaylistItems(u).first, isEmpty);
  });

  test('reorderPlaylist 重排 position', () async {
    await _insTrack(db, '/m/a.mp3', 'fpA', 'Alpha');
    await _insTrack(db, '/m/b.mp3', 'fpB', 'Beta');
    final u = await db.createPlaylist('L');
    await db.addToPlaylist(u, 'fpA');
    await db.addToPlaylist(u, 'fpB');
    await db.reorderPlaylist(u, ['fpB', 'fpA']);
    final items = await db.watchPlaylistItems(u).first;
    expect(items.map((i) => i.fp), ['fpB', 'fpA']);
  });

  test('toggleFavorite 翻转 + watchFavorites 按 addedAt 倒序', () async {
    await db.toggleFavorite('fpA');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await db.toggleFavorite('fpB');
    expect(await db.isFavorite('fpA'), isTrue);
    expect(await db.watchFavorites().first, ['fpB', 'fpA']);
    await db.toggleFavorite('fpA'); // 再次 = 取消
    expect(await db.isFavorite('fpA'), isFalse);
    expect(await db.watchFavorites().first, ['fpB']);
  });

  test('logPlayEvent 追加写入', () async {
    await db.logPlayEvent('fpA');
    await db.logPlayEvent('fpA');
    await db.logPlayEvent('fpB');
    final rows = await db.select(db.playEvents).get();
    expect(rows.length, 3);
    expect(rows.where((e) => e.trackFp == 'fpA').length, 2);
  });
}
