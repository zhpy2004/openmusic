import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/sync/sync_payload.dart';

void main() {
  const snapshot = MetadataSnapshot(
    deviceId: 'dev-a',
    playlists: [
      PlaylistRow(
        uuid: 'p1',
        name: '开车',
        createdAt: 100,
        updatedAt: 200,
        deleted: false,
      ),
    ],
    playlistItems: [
      PlaylistItemRow(
        playlistUuid: 'p1',
        trackFp: 'fp-a',
        position: 0,
        updatedAt: 210,
        deleted: false,
      ),
    ],
    favorites: [
      FavoriteRow(trackFp: 'fp-a', addedAt: 300, updatedAt: 300, deleted: false),
    ],
    overrides: [
      OverrideRow(
        trackFp: 'fp-a',
        title: '正确标题',
        artist: null,
        album: null,
        updatedAt: 400,
        deleted: false,
      ),
    ],
    playEvents: [
      PlayEventRow(trackFp: 'fp-a', playedAt: 500, eventType: 'played'),
    ],
  );

  test('JSON 往返后完全相等', () {
    final round = MetadataSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
    );
    expect(round, snapshot);
  });

  test('中文与 null 字段往返无损', () {
    final round = MetadataSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
    );
    expect(round.playlists.single.name, '开车');
    expect(round.overrides.single.title, '正确标题');
    expect(round.overrides.single.artist, isNull);
  });

  test('空快照往返', () {
    const empty = MetadataSnapshot(
      deviceId: 'dev-a',
      playlists: [],
      playlistItems: [],
      favorites: [],
      overrides: [],
      playEvents: [],
    );
    final round = MetadataSnapshot.fromJson(
      jsonDecode(jsonEncode(empty.toJson())) as Map<String, dynamic>,
    );
    expect(round, empty);
  });

  test('缺字段直接抛,不静默当默认值', () {
    expect(
      () => MetadataSnapshot.fromJson(const {'deviceId': 'x'}),
      throwsA(isA<Object>()),
    );
  });
}
