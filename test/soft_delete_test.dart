// Variable 用于 customSelect 的参数绑定;database.dart 不 re-export drift。
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(testExecutor()));
  tearDown(() => db.close());

  Future<void> addTrack(String fp) => db.upsertTrack(
    TracksCompanion.insert(
      path: '/m/$fp.mp3',
      fingerprint: fp,
      title: fp,
      sizeBytes: 1,
      mtimeMs: 1,
    ),
  );

  test('删歌单:行还在(带墓碑),但 watchPlaylists 看不到', () async {
    final uuid = await db.createPlaylist('开车');
    await db.deletePlaylist(uuid);

    expect(await db.watchPlaylists().first, isEmpty);
    final raw = await db.customSelect(
      'SELECT deleted, updated_at FROM playlists WHERE uuid = ?',
      variables: [Variable.withString(uuid)],
    ).getSingle();
    expect(raw.read<bool>('deleted'), isTrue); // 墓碑留着,才能传播删除
    expect(raw.read<int>('updated_at'), greaterThan(0));
  });

  test('移除歌单成员:墓碑留着,watchPlaylistItems 看不到', () async {
    final uuid = await db.createPlaylist('开车');
    await addTrack('fp-a');
    await db.addToPlaylist(uuid, 'fp-a');
    await db.removeFromPlaylist(uuid, 'fp-a');

    expect(await db.watchPlaylistItems(uuid).first, isEmpty);
    final raw = await db.customSelect(
      'SELECT deleted FROM playlist_items WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    expect(raw.read<bool>('deleted'), isTrue);
  });

  test('移除后再加回来:复活同一行,不留重复', () async {
    final uuid = await db.createPlaylist('开车');
    await addTrack('fp-a');
    await db.addToPlaylist(uuid, 'fp-a');
    await db.removeFromPlaylist(uuid, 'fp-a');
    await db.addToPlaylist(uuid, 'fp-a');

    final items = await db.watchPlaylistItems(uuid).first;
    expect(items.length, 1);
    final rows = await db.customSelect(
      'SELECT COUNT(*) c FROM playlist_items WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    expect(rows.read<int>('c'), 1); // 同一行复活,不是插新行
  });

  test('取消收藏:墓碑留着,三个收藏查询都看不到', () async {
    await addTrack('fp-a');
    await db.toggleFavorite('fp-a'); // 收藏
    await db.toggleFavorite('fp-a'); // 取消

    expect(await db.watchFavorites().first, isEmpty);
    expect(await db.isFavorite('fp-a'), isFalse);
    expect(await db.watchIsFavorite('fp-a').first, isFalse);

    final raw = await db.customSelect(
      'SELECT deleted FROM favorites WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    expect(raw.read<bool>('deleted'), isTrue);
  });

  test('重新收藏:复活同一行', () async {
    await addTrack('fp-a');
    await db.toggleFavorite('fp-a');
    await db.toggleFavorite('fp-a');
    await db.toggleFavorite('fp-a');

    expect(await db.isFavorite('fp-a'), isTrue);
    final rows = await db.customSelect(
      'SELECT COUNT(*) c FROM favorites WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    expect(rows.read<int>('c'), 1);
  });

  test('清除文本修正:墓碑留着,getTrackOverride 返回 null', () async {
    await addTrack('fp-a');
    await db.setTrackOverride('fp-a', title: '正确标题');
    await db.clearTrackOverride('fp-a');

    expect(await db.getTrackOverride('fp-a'), isNull);
    final raw = await db.customSelect(
      'SELECT deleted FROM track_overrides WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    expect(raw.read<bool>('deleted'), isTrue);
  });

  test('reapplyAllOverrides 跳过已删的修正', () async {
    await addTrack('fp-a');
    await db.setTrackOverride('fp-a', title: '改过的标题');
    await db.clearTrackOverride('fp-a');
    await db.applyFileTags('fp-a', title: '文件原标题', artist: '', album: '');

    await db.reapplyAllOverrides();

    final t = (await db.watchTracks('').first).single;
    expect(t.title, '文件原标题'); // 已删的修正不该被重新叠加
  });

  test('重排会 bump 成员 updatedAt(否则重排在对端不生效)', () async {
    final uuid = await db.createPlaylist('开车');
    await addTrack('fp-a');
    await addTrack('fp-b');
    await db.addToPlaylist(uuid, 'fp-a');
    await db.addToPlaylist(uuid, 'fp-b');

    final before = await db.customSelect(
      'SELECT updated_at FROM playlist_items WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await db.reorderPlaylist(uuid, ['fp-b', 'fp-a']);

    final after = await db.customSelect(
      'SELECT updated_at, position FROM playlist_items WHERE track_fp = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    expect(after.read<int>('position'), 1);
    expect(
      after.read<int>('updated_at'),
      greaterThan(before.read<int>('updated_at')),
    );
  });
}
