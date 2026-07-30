import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/metadata_merge.dart';
import 'package:openmusic/src/sync/sync_payload.dart';

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

  test('快照包含已删行(墓碑必须传出去,否则删除传播不了)', () async {
    final uuid = await db.createPlaylist('开车');
    await db.deletePlaylist(uuid);

    final snap = await db.readSyncSnapshot('dev-a');
    expect(snap.deviceId, 'dev-a');
    expect(snap.playlists.single.deleted, isTrue);
  });

  test('快照涵盖五类实体', () async {
    await addTrack('fp-a');
    final uuid = await db.createPlaylist('开车');
    await db.addToPlaylist(uuid, 'fp-a');
    await db.toggleFavorite('fp-a');
    await db.setTrackOverride('fp-a', title: '正确标题');
    await db.logPlayEventAt('fp-a', 12345);

    final snap = await db.readSyncSnapshot('dev-a');
    expect(snap.playlists.length, 1);
    expect(snap.playlistItems.length, 1);
    expect(snap.favorites.length, 1);
    expect(snap.overrides.length, 1);
    expect(snap.playEvents.single.playedAt, 12345);
  });

  test('applySyncChanges 落库后再读快照,内容等价', () async {
    await addTrack('fp-x');
    const result = MergeResult(
      playlists: [
        PlaylistRow(
          uuid: 'p9',
          name: '对端歌单',
          createdAt: 1,
          updatedAt: 2,
          deleted: false,
        ),
      ],
      playlistItems: [
        PlaylistItemRow(
          playlistUuid: 'p9',
          trackFp: 'fp-x',
          position: 0,
          updatedAt: 3,
          deleted: false,
        ),
      ],
      favorites: [
        FavoriteRow(trackFp: 'fp-x', addedAt: 4, updatedAt: 4, deleted: false),
      ],
      overrides: [
        OverrideRow(
          trackFp: 'fp-x',
          title: '同步来的标题',
          artist: null,
          album: null,
          updatedAt: 5,
          deleted: false,
        ),
      ],
      playEvents: [
        PlayEventRow(trackFp: 'fp-x', playedAt: 6, eventType: 'played'),
      ],
    );

    await db.applySyncChanges(result);

    final snap = await db.readSyncSnapshot('dev-a');
    expect(snap.playlists.single.name, '对端歌单');
    expect(snap.playlistItems.single.trackFp, 'fp-x');
    expect(snap.favorites.single.trackFp, 'fp-x');
    expect(snap.overrides.single.title, '同步来的标题');
    expect(snap.playEvents.single.playedAt, 6);
    // 文本修正落库后必须物化回 tracks,否则 UI 上看不到
    expect((await db.watchTracks('').first).single.title, '同步来的标题');
  });

  test('applySyncChanges 幂等:同一结果套两次不出错、不重复', () async {
    await addTrack('fp-x');
    const result = MergeResult(
      playlists: [],
      playlistItems: [],
      favorites: [],
      overrides: [],
      playEvents: [
        PlayEventRow(trackFp: 'fp-x', playedAt: 6, eventType: 'played'),
      ],
    );
    await db.applySyncChanges(result);
    await db.applySyncChanges(result);

    final snap = await db.readSyncSnapshot('dev-a');
    expect(snap.playEvents.length, 1);
  });

  test('空结果不触发写入', () async {
    const empty = MergeResult(
      playlists: [],
      playlistItems: [],
      favorites: [],
      overrides: [],
      playEvents: [],
    );
    await db.applySyncChanges(empty);
    final snap = await db.readSyncSnapshot('dev-a');
    expect(snap.playlists, isEmpty);
  });
}
