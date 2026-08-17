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

    // 两轮收敛:A、B 在同一个歌单里各自独有新增两个成员,四行 updatedAt
    // 完全相等(模拟同一秒内两端各自操作,正是平局规则的触发条件)。
    //
    // 实测行为(先跑出来再断言,不是先验推断):
    //   round1 onA = {x:0, y:1, z:2, w:3}   round1 onB = {z:0, w:1, x:2, y:3}
    // round 1 之后**没有出现同一设备内的重复 position**——x/y 与 z/w 是四个
    // 不同的键(playlistUuid+trackFp),彼此从不参与 LWW 比较,只是各自被追加
    // 到"对端不知道的那一侧"的本地末尾。真正的问题是:A 和 B 对同一组四个
    // 成员算出了**不同**的 position 分配(A 说 x=0,B 说 x=2)——是分歧,不是
    // 撞号。
    //
    //   round2 onA = {x:2, y:3, z:0, w:1}   round2 onB = {z:0, w:1, x:2, y:3}
    // 第二轮之后两端一致:round 1 结束时四个键在两端都已存在且 updatedAt
    // 相等(平局),`remoteWinsTie` 的反对称性(见 metadata_merge.dart 的
    // `remoteWinsTie` 计算)让两边独立选出同一个胜者(deviceId 更大的
    // device-b),于是 B 全盘保留自己的分配、A 全盘改用 B 的分配,一次收敛。
    test('两轮收敛:双方各自新增的同秒成员,第二轮后 position 分配一致且无重复', () {
      final a = snap(
        'device-a',
        items: [item('p1', 'fp-x', 0, 100), item('p1', 'fp-y', 1, 100)],
      );
      final b = snap(
        'device-b',
        items: [item('p1', 'fp-z', 0, 100), item('p1', 'fp-w', 1, 100)],
      );

      Map<String, int> positions(MetadataSnapshot s) => {
        for (final i in s.playlistItems) i.trackFp: i.position,
      };
      void expectNoDuplicatePositions(MetadataSnapshot s) {
        final ps = positions(s).values.toList();
        expect(ps.toSet().length, ps.length, reason: '同一端出现重复 position');
      }

      final onA1 = applyForTest(a, mergeMetadata(local: a, remote: b));
      final onB1 = applyForTest(b, mergeMetadata(local: b, remote: a));

      // round 1:各端内部不撞号,但两端彼此还不一致(这正是需要第二轮的原因)。
      expectNoDuplicatePositions(onA1);
      expectNoDuplicatePositions(onB1);
      expect(positions(onA1), {'fp-x': 0, 'fp-y': 1, 'fp-z': 2, 'fp-w': 3});
      expect(positions(onB1), {'fp-z': 0, 'fp-w': 1, 'fp-x': 2, 'fp-y': 3});
      expect(positions(onA1), isNot(equals(positions(onB1))));

      final onA2 = applyForTest(onA1, mergeMetadata(local: onA1, remote: onB1));
      final onB2 = applyForTest(onB1, mergeMetadata(local: onB1, remote: onA1));

      // round 2:两端 position 分配完全一致,且各端内部仍无重复。
      expectNoDuplicatePositions(onA2);
      expectNoDuplicatePositions(onB2);
      expect(positions(onA2), positions(onB2));
      expect(positions(onA2), {'fp-x': 2, 'fp-y': 3, 'fp-z': 0, 'fp-w': 1});

      // round 3:真收敛,不是还在震荡。
      final round3 = mergeMetadata(local: onA2, remote: onB2);
      expect(round3.changeCount, 0);
    });

    // 真实协议是不对称的(spec §3/计划 Task 6)——不是两端各自合并对方的
    // "原始"快照,而是:B 先把 A 的快照合并进自己库,再把**合并后**的快照
    // 回给 A;A 合并的是 B 合并后的那份,不是 B 的原始快照。
    //
    // 这条不对称路径下,"追加新成员的落点只看本地最大值"曾经真的会撞号:
    // B 把它独有的 fp-x/fp-y(来自 A)安置到 B 那边的 2、3 后回传给 A,A 若
    // 只按自己的本地最大值(2)起算 fp-z/fp-w 的追加位置,就会算出同样的
    // 2、3,与马上要从 B 采纳的 fp-x=2、fp-y=3 相撞。修复后落点改成同时避开
    // 本地与对端两边的最大值,实测(见下方 round1/round2 断言)不再撞号。
    Map<String, int> positionsOf(MetadataSnapshot s) => {
      for (final i in s.playlistItems) i.trackFp: i.position,
    };

    ({MetadataSnapshot a, MetadataSnapshot b}) realSyncRound(
      MetadataSnapshot a,
      MetadataSnapshot b,
    ) {
      // 1) A 把快照发给 B;2) B 先合并 A、更新自己,把**合并后**的快照回给 A。
      final bAfter = applyForTest(b, mergeMetadata(local: b, remote: a));
      // 3) A 合并的是 B 合并后的那份。
      final aAfter = applyForTest(a, mergeMetadata(local: a, remote: bAfter));
      return (a: aAfter, b: bAfter);
    }

    test('真实协议路径:不对称往返,两端各自内部 position 无重复', () {
      final a0 = snap(
        'device-a',
        items: [item('p1', 'fp-x', 0, 100), item('p1', 'fp-y', 1, 100)],
      );
      final b0 = snap(
        'device-b',
        items: [item('p1', 'fp-z', 0, 100), item('p1', 'fp-w', 1, 100)],
      );

      final round1 = realSyncRound(a0, b0);
      final pa1 = positionsOf(round1.a);
      final pb1 = positionsOf(round1.b);

      void expectNoDuplicatePositions(Map<String, int> ps, String label) {
        final values = ps.values.toList();
        expect(
          values.toSet().length,
          values.length,
          reason: '$label 出现重复 position: $ps',
        );
      }

      // 实测(修复后):A 的追加落点让到了本地(2)与对端(4)两边最大值
      // 之后,B 未参与本轮种子计算所以仍是它自己的 max+1。
      expect(pa1, {'fp-x': 2, 'fp-y': 3, 'fp-z': 4, 'fp-w': 5});
      expect(pb1, {'fp-z': 0, 'fp-w': 1, 'fp-x': 2, 'fp-y': 3});
      expectNoDuplicatePositions(pa1, 'A(round1)');
      expectNoDuplicatePositions(pb1, 'B(round1)');

      final round2 = realSyncRound(round1.a, round1.b);
      final pa2 = positionsOf(round2.a);
      final pb2 = positionsOf(round2.b);
      // 实测:第二轮里 fp-z/fp-w 在两端都已存在且 updatedAt 相等(平局),
      // 平局统一判给 device-b,A 全盘改用 B 的 position,一次收敛。
      expect(pa2, {'fp-x': 2, 'fp-y': 3, 'fp-z': 0, 'fp-w': 1});
      expectNoDuplicatePositions(pa2, 'A(round2)');
      expectNoDuplicatePositions(pb2, 'B(round2)');
      expect(pa2, pb2, reason: '第二轮之后两端 position 分配应完全一致');

      final round3ChangeOnB = mergeMetadata(local: round2.b, remote: round2.a);
      final round3ChangeOnA = mergeMetadata(
        local: round2.a,
        remote: applyForTest(round2.b, round3ChangeOnB),
      );
      expect(round3ChangeOnB.changeCount, 0, reason: '第三轮 B 侧应无变更(已收敛)');
      expect(round3ChangeOnA.changeCount, 0, reason: '第三轮 A 侧应无变更(已收敛)');
    });
  });
}

List<String> _sortedNames(MetadataSnapshot s) =>
    s.playlists.map((p) => '${p.uuid}:${p.name}:${p.deleted}').toList()..sort();

List<String> _sortedItemKeys(MetadataSnapshot s) =>
    s.playlistItems.map((i) => '${i.key}:${i.deleted}').toList()..sort();

List<String> _sortedFavKeys(MetadataSnapshot s) =>
    s.favorites.map((f) => '${f.trackFp}:${f.deleted}').toList()..sort();
