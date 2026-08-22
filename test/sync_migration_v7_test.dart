import 'dart:io';

// Variable 来自 drift,database.dart 不 re-export —— 少这行编译不过。
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

/// v7 只新建表、不碰老表,所以"退化"只需 DROP 掉这张新表。
/// 但 v1→v7 跳级仍要测:v6 那次的教训是 onUpgrade 的分支组合容易出错。
void main() {
  late File file;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('om-mig-v7');
    file = File('${dir.path}/openmusic.sqlite');
  });

  tearDown(() async {
    if (await file.exists()) await file.delete();
  });

  Future<void> expectMirrorFlowWorks(AppDatabase db) async {
    final uuid = await db.createPlaylist('开车');
    await db.setPlaylistMirrored(uuid, true);
    expect(await db.mirroredPlaylistUuids(), {uuid});
    await db.setPlaylistMirrored(uuid, false);
    expect(await db.mirroredPlaylistUuids(), isEmpty);
  }

  test('v6→v7:建镜像表,旧数据无损', () async {
    final v6 = AppDatabase(testFileExecutor(file.path));
    final uuid = await v6.createPlaylist('老歌单');
    await v6.customStatement('DROP TABLE IF EXISTS mirrored_playlists');
    await v6.customStatement('PRAGMA user_version = 6');
    await v6.close();

    final db = AppDatabase(testFileExecutor(file.path));
    final playlists = await db.watchPlaylists().first;
    expect(playlists.single.name, '老歌单');
    expect(playlists.single.uuid, uuid);
    expect(await db.mirroredPlaylistUuids(), isEmpty); // 新表建出来了,是空的
    await expectMirrorFlowWorks(db);
    await db.close();
  });

  test('v1→v7 跳级:老表由 createTable 补出、镜像表也建出,链路可用', () async {
    final v1 = AppDatabase(testFileExecutor(file.path));
    await v1.customStatement(
      "INSERT INTO tracks (path, fingerprint, title, artist, album, "
      "album_artist, duration_ms, size_bytes, mtime_ms) "
      "VALUES ('/m/a.mp3', 'fp-a', '老歌', '歌手', '', '', 0, 1, 1)",
    );
    for (final t in const [
      'mirrored_playlists',
      'peers',
      'local_device',
      'app_settings',
      'track_overrides',
      'play_events',
      'favorites',
      'playlist_items',
      'playlists',
    ]) {
      await v1.customStatement('DROP TABLE IF EXISTS $t');
    }
    await v1.customStatement('PRAGMA user_version = 1');
    await v1.close();

    final db = AppDatabase(testFileExecutor(file.path));
    expect(db.schemaVersion, 7);
    final tracks = await db.watchTracks('').first;
    expect(tracks.single.title, '老歌'); // v1 时代的数据无损
    await expectMirrorFlowWorks(db);

    // 软删链路仍可用(证明补出来的表与迁移出来的表功能等价)
    await db.toggleFavorite('fp-a');
    expect(await db.isFavorite('fp-a'), isTrue);
    await db.toggleFavorite('fp-a');
    expect(await db.isFavorite('fp-a'), isFalse);

    final row = await db.customSelect(
      'SELECT COUNT(*) c FROM tracks WHERE fingerprint = ?',
      variables: [Variable.withString('fp-a')],
    ).getSingle();
    expect(row.read<int>('c'), 1);
    await db.close();
  });
}
