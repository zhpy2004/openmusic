import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/sync/metadata_merge.dart';
import 'package:openmusic/src/sync/sync_payload.dart';

MetadataSnapshot snap(
  String deviceId, {
  List<PlaylistRow> playlists = const [],
  List<PlaylistItemRow> items = const [],
  List<FavoriteRow> favorites = const [],
  List<OverrideRow> overrides = const [],
  List<PlayEventRow> events = const [],
}) => MetadataSnapshot(
  deviceId: deviceId,
  playlists: playlists,
  playlistItems: items,
  favorites: favorites,
  overrides: overrides,
  playEvents: events,
);

PlaylistRow pl(
  String uuid,
  String name,
  int updatedAt, {
  bool deleted = false,
}) => PlaylistRow(
  uuid: uuid,
  name: name,
  createdAt: 1,
  updatedAt: updatedAt,
  deleted: deleted,
);

PlaylistItemRow item(
  String playlist,
  String fp,
  int position,
  int updatedAt, {
  bool deleted = false,
}) => PlaylistItemRow(
  playlistUuid: playlist,
  trackFp: fp,
  position: position,
  updatedAt: updatedAt,
  deleted: deleted,
);

FavoriteRow fav(String fp, int updatedAt, {bool deleted = false}) =>
    FavoriteRow(
      trackFp: fp,
      addedAt: updatedAt,
      updatedAt: updatedAt,
      deleted: deleted,
    );

void main() {
  group('歌单', () {
    test('对端更新则采纳对端的名字', () {
      final r = mergeMetadata(
        local: snap('a', playlists: [pl('p1', '旧名', 100)]),
        remote: snap('b', playlists: [pl('p1', '新名', 200)]),
      );
      expect(r.playlists.single.name, '新名');
    });

    test('本地更新则不产生变更', () {
      final r = mergeMetadata(
        local: snap('a', playlists: [pl('p1', '新名', 300)]),
        remote: snap('b', playlists: [pl('p1', '旧名', 100)]),
      );
      expect(r.playlists, isEmpty);
    });

    test('对端只有的歌单会被引入', () {
      final r = mergeMetadata(
        local: snap('a'),
        remote: snap('b', playlists: [pl('p2', '对端歌单', 100)]),
      );
      expect(r.playlists.single.uuid, 'p2');
    });

    test('对端删除会传播过来', () {
      final r = mergeMetadata(
        local: snap('a', playlists: [pl('p1', '开车', 100)]),
        remote: snap('b', playlists: [pl('p1', '开车', 200, deleted: true)]),
      );
      expect(r.playlists.single.deleted, isTrue);
    });

    test('本地已删,对端的旧数据不会把它复活', () {
      final r = mergeMetadata(
        local: snap('a', playlists: [pl('p1', '开车', 300, deleted: true)]),
        remote: snap('b', playlists: [pl('p1', '开车', 100)]),
      );
      expect(r.playlists, isEmpty); // 本地更新,无需变更
    });
  });

  group('歌单成员', () {
    test('双方各加各的,合并后都在(裁决 1 的核心价值)', () {
      final r = mergeMetadata(
        local: snap('a', items: [item('p1', 'fp-1', 0, 100)]),
        remote: snap('b', items: [item('p1', 'fp-2', 0, 100)]),
      );
      expect(r.playlistItems.single.trackFp, 'fp-2');
    });

    test('对端新增的成员追加到本地末尾,不与现有 position 撞号', () {
      final r = mergeMetadata(
        local: snap(
          'a',
          items: [item('p1', 'fp-1', 0, 100), item('p1', 'fp-2', 1, 100)],
        ),
        remote: snap(
          'b',
          items: [item('p1', 'fp-3', 0, 100), item('p1', 'fp-4', 1, 100)],
        ),
      );
      final positions = {
        for (final i in r.playlistItems) i.trackFp: i.position,
      };
      expect(positions['fp-3'], 2);
      expect(positions['fp-4'], 3); // 保住对端内部相对顺序
    });

    test('两边都有的成员用胜者的 position', () {
      final r = mergeMetadata(
        local: snap('a', items: [item('p1', 'fp-1', 0, 100)]),
        remote: snap('b', items: [item('p1', 'fp-1', 5, 200)]),
      );
      expect(r.playlistItems.single.position, 5);
    });

    test('对端移除会传播', () {
      final r = mergeMetadata(
        local: snap('a', items: [item('p1', 'fp-1', 0, 100)]),
        remote: snap('b', items: [item('p1', 'fp-1', 0, 200, deleted: true)]),
      );
      expect(r.playlistItems.single.deleted, isTrue);
    });

    test('已删成员不会被对端旧数据复活', () {
      final r = mergeMetadata(
        local: snap('a', items: [item('p1', 'fp-1', 0, 300, deleted: true)]),
        remote: snap('b', items: [item('p1', 'fp-1', 0, 100)]),
      );
      expect(r.playlistItems, isEmpty);
    });
  });

  group('收藏与文本修正', () {
    test('对端取消收藏会传播', () {
      final r = mergeMetadata(
        local: snap('a', favorites: [fav('fp-1', 100)]),
        remote: snap('b', favorites: [fav('fp-1', 200, deleted: true)]),
      );
      expect(r.favorites.single.deleted, isTrue);
    });

    test('文本修正按 updatedAt 整行替换', () {
      final r = mergeMetadata(
        local: snap(
          'a',
          overrides: const [
            OverrideRow(
              trackFp: 'fp-1',
              title: '旧',
              artist: null,
              album: null,
              updatedAt: 100,
              deleted: false,
            ),
          ],
        ),
        remote: snap(
          'b',
          overrides: const [
            OverrideRow(
              trackFp: 'fp-1',
              title: '新',
              artist: '歌手',
              album: null,
              updatedAt: 200,
              deleted: false,
            ),
          ],
        ),
      );
      expect(r.overrides.single.title, '新');
      expect(r.overrides.single.artist, '歌手');
    });
  });

  group('播放记录', () {
    test('取并集,已有的不重复引入', () {
      final r = mergeMetadata(
        local: snap(
          'a',
          events: const [
            PlayEventRow(trackFp: 'fp-1', playedAt: 1, eventType: 'played'),
          ],
        ),
        remote: snap(
          'b',
          events: const [
            PlayEventRow(trackFp: 'fp-1', playedAt: 1, eventType: 'played'),
            PlayEventRow(trackFp: 'fp-1', playedAt: 2, eventType: 'played'),
          ],
        ),
      );
      expect(r.playEvents.length, 1);
      expect(r.playEvents.single.playedAt, 2);
    });
  });

  group('平局', () {
    test('updatedAt 相等且内容不同时,deviceId 字典序大者胜', () {
      final rOnA = mergeMetadata(
        local: snap('device-a', playlists: [pl('p1', 'A 的名字', 100)]),
        remote: snap('device-b', playlists: [pl('p1', 'B 的名字', 100)]),
      );
      // b > a,所以对端胜:本地要改成 B 的名字
      expect(rOnA.playlists.single.name, 'B 的名字');

      final rOnB = mergeMetadata(
        local: snap('device-b', playlists: [pl('p1', 'B 的名字', 100)]),
        remote: snap('device-a', playlists: [pl('p1', 'A 的名字', 100)]),
      );
      // 同样是 b 胜:本地已经是赢家,无变更
      expect(rOnB.playlists, isEmpty);
    });

    test('内容完全相同则不产生变更', () {
      final r = mergeMetadata(
        local: snap('device-a', playlists: [pl('p1', '同名', 100)]),
        remote: snap('device-b', playlists: [pl('p1', '同名', 100)]),
      );
      expect(r.playlists, isEmpty);
    });
  });

  group('性质', () {
    // 两端各自合并后必须收敛到同一状态 —— 分布式合并唯一真正要证明的性质。
    test('收敛性:两端各自合并后状态一致', () {
      final a = snap(
        'device-a',
        playlists: [pl('p1', 'A 名', 100), pl('p2', '只有 A', 50)],
        items: [item('p1', 'fp-1', 0, 100)],
        favorites: [fav('fp-1', 100)],
      );
      final b = snap(
        'device-b',
        playlists: [pl('p1', 'B 名', 100), pl('p3', '只有 B', 60)],
        items: [item('p1', 'fp-2', 0, 120)],
        favorites: [fav('fp-2', 90)],
      );

      final onA = applyForTest(a, mergeMetadata(local: a, remote: b));
      final onB = applyForTest(b, mergeMetadata(local: b, remote: a));

      expect(_sortedNames(onA), _sortedNames(onB));
      expect(_sortedItemKeys(onA), _sortedItemKeys(onB));
      expect(_sortedFavKeys(onA), _sortedFavKeys(onB));
    });

    test('幂等性:同一份快照合并两次,第二次零变更', () {
      final a = snap('device-a', playlists: [pl('p1', 'A 名', 100)]);
      final b = snap('device-b', playlists: [pl('p1', 'B 名', 200)]);

      final first = mergeMetadata(local: a, remote: b);
      expect(first.changeCount, greaterThan(0));

      final merged = applyForTest(a, first);
      final second = mergeMetadata(local: merged, remote: b);
      expect(second.changeCount, 0);
    });
  });
}

List<String> _sortedNames(MetadataSnapshot s) =>
    s.playlists.map((p) => '${p.uuid}:${p.name}:${p.deleted}').toList()..sort();

List<String> _sortedItemKeys(MetadataSnapshot s) =>
    s.playlistItems.map((i) => '${i.key}:${i.deleted}').toList()..sort();

List<String> _sortedFavKeys(MetadataSnapshot s) =>
    s.favorites.map((f) => '${f.trackFp}:${f.deleted}').toList()..sort();
