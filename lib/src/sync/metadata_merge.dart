import 'sync_payload.dart';

/// 合并结果 = **本地需要写入的行**(不是全量)。
///
/// 只带变更行有两个好处:落库时写得少;UI 摘要天然就是"本地实际发生的变更数",
/// 于是"点了同步但什么都没变"与"同步失败"能区分开。
class MergeResult {
  const MergeResult({
    required this.playlists,
    required this.playlistItems,
    required this.favorites,
    required this.overrides,
    required this.playEvents,
  });

  final List<PlaylistRow> playlists;
  final List<PlaylistItemRow> playlistItems;
  final List<FavoriteRow> favorites;
  final List<OverrideRow> overrides;
  final List<PlayEventRow> playEvents;

  int get changeCount =>
      playlists.length +
      playlistItems.length +
      favorites.length +
      overrides.length +
      playEvents.length;

  bool get isEmpty => changeCount == 0;
}

/// 把合并结果套用到快照上 —— **仅供测试**验证收敛性/幂等性,生产路径走
/// `AppDatabase.applySyncChanges`。放在这里是为了让性质测试不必依赖数据库。
MetadataSnapshot applyForTest(MetadataSnapshot base, MergeResult result) {
  Map<K, V> indexed<K, V>(List<V> rows, K Function(V) key) => {
    for (final r in rows) key(r): r,
  };

  final playlists = indexed(base.playlists, (PlaylistRow p) => p.uuid);
  for (final p in result.playlists) {
    playlists[p.uuid] = p;
  }
  final items = indexed(base.playlistItems, (PlaylistItemRow i) => i.key);
  for (final i in result.playlistItems) {
    items[i.key] = i;
  }
  final favorites = indexed(base.favorites, (FavoriteRow f) => f.trackFp);
  for (final f in result.favorites) {
    favorites[f.trackFp] = f;
  }
  final overrides = indexed(base.overrides, (OverrideRow o) => o.trackFp);
  for (final o in result.overrides) {
    overrides[o.trackFp] = o;
  }
  final events = indexed(base.playEvents, (PlayEventRow e) => e.key);
  for (final e in result.playEvents) {
    events[e.key] = e;
  }

  return MetadataSnapshot(
    deviceId: base.deviceId,
    playlists: playlists.values.toList(),
    playlistItems: items.values.toList(),
    favorites: favorites.values.toList(),
    overrides: overrides.values.toList(),
    playEvents: events.values.toList(),
  );
}

/// 纯函数合并:给定本地与对端快照,算出**本地要写入哪些行**。
///
/// 不碰数据库、不碰网络、不看时钟 —— 全部输入都在参数里,所以行为可完整单测
/// (母 spec §9 的硬要求)。
MergeResult mergeMetadata({
  required MetadataSnapshot local,
  required MetadataSnapshot remote,
}) {
  // 平局(updatedAt 相等且内容不同)时 deviceId 字典序大者胜。
  // 没有这条规则两端会各留各的,同步完仍不一致、下次还不一致——永不收敛。
  final remoteWinsTie = remote.deviceId.compareTo(local.deviceId) > 0;

  bool remoteWins(int remoteAt, int localAt) =>
      remoteAt > localAt || (remoteAt == localAt && remoteWinsTie);

  // --- 歌单:按 uuid 整体 LWW(名字 + 墓碑) ---
  final localPlaylists = {for (final p in local.playlists) p.uuid: p};
  final playlists = <PlaylistRow>[];
  for (final r in remote.playlists) {
    final l = localPlaylists[r.uuid];
    if (l == null) {
      playlists.add(r);
    } else if (l != r && remoteWins(r.updatedAt, l.updatedAt)) {
      playlists.add(r);
    }
  }

  // --- 歌单成员:按 (歌单, 指纹) 按行 LWW ---
  final localItems = {for (final i in local.playlistItems) i.key: i};
  // 每个歌单当前最大 position(含已删行,避免复活时撞号)。
  //
  // 追加落点要同时避开**本地已有**和**即将从对端采纳**的 position:真实同步
  // 协议是不对称的(先由对端把我方快照合并进它自己库,再把它合并后的快照
  // 回给我方) —— 这份"对端回传的快照"里,对端早已把它自己独有的新成员
  // 安置到了它那边的 max+1 位置,那些位置数字会随对端的行原样被我方采纳
  // (双方都存在的项走 remoteWins 分支,直接沿用 r.position)。如果这里的
  // 种子只看本地最大值,我方为"对端独有、本地没有"的项重新分配的追加位置
  // 就可能与"对端已有、马上要被我方采纳"的位置撞在一起,导致
  // ORDER BY position 顺序未定义。
  final nextPosition = <String, int>{};
  void bumpNextPosition(PlaylistItemRow i) {
    final cur = nextPosition[i.playlistUuid];
    if (cur == null || i.position >= cur) {
      nextPosition[i.playlistUuid] = i.position + 1;
    }
  }

  for (final i in local.playlistItems) {
    bumpNextPosition(i);
  }
  for (final i in remote.playlistItems) {
    bumpNextPosition(i);
  }
  final playlistItems = <PlaylistItemRow>[];
  // 按对端 position 升序处理,保住对端内部的相对顺序
  final remoteItems = [...remote.playlistItems]
    ..sort((a, b) => a.position.compareTo(b.position));
  for (final r in remoteItems) {
    final l = localItems[r.key];
    if (l == null) {
      if (r.deleted) {
        // 本地从没有过这一项,对端的墓碑照收:否则两端"有没有这一行"不一致,
        // 下一轮对端又会把它当新增推过来。
        playlistItems.add(r);
        continue;
      }
      final pos = nextPosition[r.playlistUuid] ?? 0;
      nextPosition[r.playlistUuid] = pos + 1;
      playlistItems.add(r.copyWith(position: pos)); // 追加到本地末尾
      continue;
    }
    if (l != r && remoteWins(r.updatedAt, l.updatedAt)) {
      playlistItems.add(r); // 两边都有:用胜者的 position 与墓碑
    }
  }

  // --- 收藏:按指纹按行 LWW ---
  final localFavorites = {for (final f in local.favorites) f.trackFp: f};
  final favorites = <FavoriteRow>[];
  for (final r in remote.favorites) {
    final l = localFavorites[r.trackFp];
    if (l == null) {
      favorites.add(r);
    } else if (l != r && remoteWins(r.updatedAt, l.updatedAt)) {
      favorites.add(r);
    }
  }

  // --- 文本修正:按指纹按行 LWW,整行替换 ---
  final localOverrides = {for (final o in local.overrides) o.trackFp: o};
  final overrides = <OverrideRow>[];
  for (final r in remote.overrides) {
    final l = localOverrides[r.trackFp];
    if (l == null) {
      overrides.add(r);
    } else if (l != r && remoteWins(r.updatedAt, l.updatedAt)) {
      overrides.add(r);
    }
  }

  // --- 播放记录:取并集(自然键去重) ---
  final localEventKeys = {for (final e in local.playEvents) e.key};
  final playEvents = [
    for (final r in remote.playEvents)
      if (!localEventKeys.contains(r.key)) r,
  ];

  return MergeResult(
    playlists: playlists,
    playlistItems: playlistItems,
    favorites: favorites,
    overrides: overrides,
    playEvents: playEvents,
  );
}
