import 'dart:math';

import 'package:drift/drift.dart';

import '../sync/metadata_merge.dart';
import '../sync/sync_payload.dart';

part 'database.g.dart';

class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  TextColumn get fingerprint => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant(''))();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get albumArtist => text().withDefault(const Constant(''))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  IntColumn get sizeBytes => integer()();
  IntColumn get mtimeMs => integer()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

class ScanRoots extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
}

class Playlists extends Table {
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  /// 软删墓碑:删除不真删行,否则删除无法跨设备传播(会被对端"复活")。
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {uuid};
}

class PlaylistItems extends Table {
  TextColumn get playlistUuid => text()();
  TextColumn get trackFp => text()(); // 内容指纹引用,非 tracks.id
  IntColumn get position => integer()();
  /// 本行自己的最后改动时刻 —— 成员是**按行 LWW** 合并的,不跟歌单整体走。
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  List<Set<Column>> get uniqueKeys => [
    {playlistUuid, trackFp},
  ];
}

class Favorites extends Table {
  TextColumn get trackFp => text()();
  IntColumn get addedAt => integer()(); // 保留:展示排序用
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {trackFp};
}

class PlayEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackFp => text()();
  IntColumn get playedAt => integer()();
  TextColumn get eventType => text().withDefault(const Constant('played'))();
}

/// 文本修正覆盖层。刮削不改音频字节(改了会动指纹),文本修正存这里,
/// 再物化回 tracks 行显示。fp 为键 + updatedAt ⇒ M3 可按行 LWW 同步。
/// 字段为 null = 该项不覆盖,沿用文件原始标签。
class TrackOverrides extends Table {
  TextColumn get trackFp => text()();
  TextColumn get title => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get album => text().nullable()();
  IntColumn get updatedAt => integer()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {trackFp};
}

/// 设备本地设置(key-value)。目前只存 `locale`,后续偏好可复用。
/// 属于设备本地状态,不参与 M3 跨设备同步。
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 本机设备身份(单行表,id 恒为 0)。M3 跨设备身份的本地一半。
class LocalDevice extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 已配对的对端设备。sharedKey 是 base64 的 32 字节 HMAC 密钥。
/// 在线状态**不落库**(来自 mDNS 实时流);lastAddress/lastContactAt 只在
/// 配对成功与「测试连接」成功时写,属低频——按 tick 写会触发表级流失效风暴。
class Peers extends Table {
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text()();
  TextColumn get platform => text()();
  TextColumn get sharedKey => text()();
  IntColumn get pairedAt => integer()();
  TextColumn get lastAddress => text().nullable()();
  IntColumn get lastContactAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {deviceId};
}

/// 歌单成员 + 关联曲目(可能为 null=文件缺失/未扫描到)。
class PlaylistEntry {
  const PlaylistEntry({required this.fp, required this.position, this.track});
  final String fp;
  final int position;
  final Track? track;
}

@DriftDatabase(
  tables: [
    Tracks,
    ScanRoots,
    Playlists,
    PlaylistItems,
    Favorites,
    PlayEvents,
    TrackOverrides,
    AppSettings,
    LocalDevice,
    Peers,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  final _rnd = Random();

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_play_events_natural_key '
        'ON play_events (track_fp, played_at, event_type)',
      );
    },
    onUpgrade: (m, from, to) async {
      // v1→v2:只新建 M2-A 的四张表,现有 tracks/scan_roots 原样保留。
      if (from < 2) {
        await m.createTable(playlists);
        await m.createTable(playlistItems);
        await m.createTable(favorites);
        await m.createTable(playEvents);
      }
      // v2→v3:只新建 M2-B 的覆盖表,其余表原样保留。
      if (from < 3) {
        await m.createTable(trackOverrides);
      }
      // v3→v4:只新建本地设置表,其余表原样保留。
      if (from < 4) {
        await m.createTable(appSettings);
      }
      // v4→v5:只新建 M3-A 的两张表,其余表原样保留。
      if (from < 5) {
        await m.createTable(localDevice);
        await m.createTable(peers);
      }
      // v5→v6:M3-B 的软删列 + play_events 去重索引。
      if (from < 6) {
        // 只给**真正的旧结构**补列:上面 from<2 / from<3 的块用的是 drift 的
        // m.createTable,它永远建**当前**(v6)形状 —— 那些表已经自带软删列了,
        // 再 addColumn 会撞 duplicate column name,整个迁移中断、库打不开。
        // 受影响的是从 v1(playlists 等四表)与 v2(track_overrides)升上来的库
        // ——这两个版本(v0.1.0-m1、v0.2.0-m2a)已公开发布,必须兼容。
        if (from >= 2) {
          await m.addColumn(playlists, playlists.deleted);
          await m.addColumn(playlistItems, playlistItems.updatedAt);
          await m.addColumn(playlistItems, playlistItems.deleted);
          await m.addColumn(favorites, favorites.updatedAt);
          await m.addColumn(favorites, favorites.deleted);
        }
        if (from >= 3) {
          await m.addColumn(trackOverrides, trackOverrides.deleted);
        }

        // 回填 updatedAt(不能留 0:它要参与 LWW 比较,0 会永远输)。
        // favorites 用自己的 addedAt(就是这行的产生时刻);
        // playlist_items 没有历史时间,用所属歌单的 updatedAt —— 比拍一个
        // 迁移时刻更接近真相(歌单最后改动时间即其成员最后改动时间)。
        await customStatement(
          'UPDATE favorites SET updated_at = added_at WHERE updated_at = 0',
        );
        await customStatement(
          'UPDATE playlist_items SET updated_at = ('
          '  SELECT updated_at FROM playlists WHERE playlists.uuid = playlist_items.playlist_uuid'
          ') WHERE updated_at = 0',
        );
        // 歌单被删过而成员还在的孤儿行:上面子查询返回 NULL,兜底成迁移时刻。
        await customStatement(
          'UPDATE playlist_items SET updated_at = ${DateTime.now().millisecondsSinceEpoch} '
          'WHERE updated_at IS NULL OR updated_at = 0',
        );

        // **先去重再建唯一索引**:已有同键重复行会让 CREATE UNIQUE INDEX 直接失败、
        // 迁移中断。保留每组 rowid 最小的一条。
        await customStatement(
          'DELETE FROM play_events WHERE id NOT IN ('
          '  SELECT MIN(id) FROM play_events GROUP BY track_fp, played_at, event_type'
          ')',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_play_events_natural_key '
          'ON play_events (track_fp, played_at, event_type)',
        );
      }
    },
  );

  /// 读设置项;不存在返回 null。
  Future<String?> getSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 写设置项(存在即覆盖)。
  Future<void> setSetting(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSetting(key: key, value: value));

  /// 监听某个设置项,供 UI 即时响应(如切语言)。
  Stream<String?> watchSetting(String key) => (select(
    appSettings,
  )..where((t) => t.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  // insertOnConflictUpdate 默认只按主键（id）判定冲突；path 是单独的唯一约束，
  // 必须显式指定 conflict target，否则同 path 二次写入会因主键不冲突而尝试
  // 插入新行，进而撞上 path 的 UNIQUE 约束报错。
  Future<void> upsertTrack(TracksCompanion entry) => into(
    tracks,
  ).insert(entry, onConflict: DoUpdate((_) => entry, target: [tracks.path]));

  /// 批量 upsert：单事务、单次流通知。扫描器逐文件 await upsertTrack 会让
  /// 每个活跃 watchTracks 流每文件全量重查一次（表级失效，万级文件 O(n²)），
  /// 且逐条隐式事务逐条 journal commit——批量把两者都收敛到每批一次。
  Future<void> batchUpsertTracks(List<TracksCompanion> entries) => batch((b) {
    for (final e in entries) {
      b.insert(
        tracks,
        e,
        onConflict: DoUpdate((_) => e, target: [tracks.path]),
      );
    }
  });

  Stream<List<Track>> watchTracks(String query) {
    // NOCASE：BINARY collation 会把所有大写排到所有小写之前
    //（[apple, Zebra, Banana] → [Banana, Zebra, apple]）。
    final q = select(tracks)
      ..orderBy([
        (t) => OrderingTerm(expression: t.title.collate(Collate.noCase)),
      ]);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where(
        (t) => t.title.like(like) | t.artist.like(like) | t.album.like(like),
      );
    }
    return q.watch();
  }

  /// 增量扫描用：path → (mtimeMs, sizeBytes)
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> pathIndex() async {
    final rows = await (selectOnly(
      tracks,
    )..addColumns([tracks.path, tracks.mtimeMs, tracks.sizeBytes])).get();
    return {
      for (final r in rows)
        r.read(tracks.path)!: (
          mtimeMs: r.read(tracks.mtimeMs)!,
          sizeBytes: r.read(tracks.sizeBytes)!,
        ),
    };
  }

  Future<void> deleteTracksNotIn(Set<String> keepPaths) =>
      // 单事务：多分块只 journal commit 一次，流通知也只发一次。
      transaction(() async {
        final existing = (await pathIndex()).keys.toSet();
        final toDelete = existing.difference(keepPaths).toList();
        for (var i = 0; i < toDelete.length; i += 500) {
          final chunk = toDelete.sublist(
            i,
            i + 500 > toDelete.length ? toDelete.length : i + 500,
          );
          await (delete(tracks)..where((t) => t.path.isIn(chunk))).go();
        }
      });

  Future<void> addScanRoot(String path) => into(scanRoots).insert(
    ScanRootsCompanion.insert(path: path),
    mode: InsertMode.insertOrIgnore,
  );

  Future<void> removeScanRoot(String path) =>
      (delete(scanRoots)..where((r) => r.path.equals(path))).go();

  Stream<List<String>> watchScanRoots() =>
      select(scanRoots).watch().map((rows) => rows.map((r) => r.path).toList());

  // 时间戳(微秒)前缀便于排序/调试 + 真随机后缀保唯一。后缀必须独立熵:
  // 时钟粒度粗时 microsecondsSinceEpoch 会连续相同,派生随机会碰撞(→ 主键/同步身份重复)。
  String _newUuid() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final r = _rnd.nextInt(0x7fffffff);
    return '$ms-${r.toRadixString(16)}';
  }

  Future<String> createPlaylist(String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final uuid = _newUuid();
    await into(playlists).insert(
      PlaylistsCompanion.insert(
        uuid: uuid,
        name: name,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return uuid;
  }

  Future<void> renamePlaylist(String uuid, String name) =>
      (update(playlists)..where((p) => p.uuid.equals(uuid))).write(
        PlaylistsCompanion(
          name: Value(name),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  // 软删而非真删:否则删除无法跨设备传播(对端会拿它那份旧数据把已删的歌单
  // "复活")。成员不跟着软删:歌单行本身就是墓碑,成员留原样——若对端稍后
  // "复活"了这个歌单(它那边 updatedAt 更新),成员还在,不用重建。
  Future<void> deletePlaylist(String uuid) =>
      (update(playlists)..where((p) => p.uuid.equals(uuid))).write(
        PlaylistsCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Stream<List<Playlist>> watchPlaylists() => (select(playlists)
        ..where((p) => p.deleted.equals(false))
        ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]))
      .watch();

  Future<void> _bumpPlaylist(String uuid) =>
      (update(playlists)..where((p) => p.uuid.equals(uuid))).write(
        PlaylistsCompanion(
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> addToPlaylist(String uuid, String fp) => transaction(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final exists =
        await (select(
              playlistItems,
            )..where((i) => i.playlistUuid.equals(uuid) & i.trackFp.equals(fp)))
            .getSingleOrNull();
    // 已在歌单且未删 = 完全 no-op:不写、不 bump。否则重复 add 会让歌单假装
    // "被改过"跳到列表顶,且 LWW 会拿一个未变化的歌单覆盖对端真实改动。
    if (exists != null && !exists.deleted) return;

    // max 要把已删行也算进去:复活时若沿用旧 position 可能与现存行撞号。
    final maxPos =
        await (selectOnly(playlistItems)
              ..addColumns([playlistItems.position.max()])
              ..where(playlistItems.playlistUuid.equals(uuid)))
            .map((r) => r.read(playlistItems.position.max()))
            .getSingleOrNull();
    final nextPos = (maxPos ?? -1) + 1;

    if (exists == null) {
      await into(playlistItems).insert(
        PlaylistItemsCompanion.insert(
          playlistUuid: uuid,
          trackFp: fp,
          position: nextPos,
          updatedAt: Value(now),
        ),
      );
    } else {
      // 复活同一行(不是插新行),否则唯一约束会撞,且会留下两份历史。
      await (update(playlistItems)..where(
            (i) => i.playlistUuid.equals(uuid) & i.trackFp.equals(fp),
          ))
          .write(
            PlaylistItemsCompanion(
              deleted: const Value(false),
              position: Value(nextPos),
              updatedAt: Value(now),
            ),
          );
    }
    await _bumpPlaylist(uuid);
  });

  // 软删而非真删:同上,否则移除无法跨设备传播。
  Future<void> removeFromPlaylist(String uuid, String fp) =>
      transaction(() async {
        await (update(playlistItems)..where(
              (i) => i.playlistUuid.equals(uuid) & i.trackFp.equals(fp),
            ))
            .write(
              PlaylistItemsCompanion(
                deleted: const Value(true),
                updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
              ),
            );
        await _bumpPlaylist(uuid);
      });

  /// 重排:[fpsInOrder] 必须是该歌单**当前全部成员**的完整期望顺序。
  /// 传子集会让未列出的项保留旧 position → 可能出现重复 position(排序不稳:
  /// watchPlaylistItems 的 ORDER BY position 在重复值上顺序未定义)。
  /// UI(ReorderableListView)总传全量顺序,满足此前提。
  Future<void> reorderPlaylist(String uuid, List<String> fpsInOrder) =>
      transaction(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var i = 0; i < fpsInOrder.length; i++) {
          // 必须 bump 每个成员的 updatedAt:成员是按行 LWW 合并的,行没变化
          // 对端就不会采纳新 position,重排等于同步不出去。
          await (update(playlistItems)..where(
                (it) =>
                    it.playlistUuid.equals(uuid) &
                    it.trackFp.equals(fpsInOrder[i]),
              ))
              .write(
                PlaylistItemsCompanion(
                  position: Value(i),
                  updatedAt: Value(now),
                ),
              );
        }
        await _bumpPlaylist(uuid);
      });

  Stream<List<PlaylistEntry>> watchPlaylistItems(String uuid) {
    final q =
        select(playlistItems).join([
            leftOuterJoin(
              tracks,
              tracks.fingerprint.equalsExp(playlistItems.trackFp),
            ),
          ])
          ..where(
            playlistItems.playlistUuid.equals(uuid) &
                playlistItems.deleted.equals(false),
          )
          ..orderBy([OrderingTerm.asc(playlistItems.position)]);
    return q.watch().map(
      (rows) => rows
          .map(
            (r) => PlaylistEntry(
              fp: r.readTable(playlistItems).trackFp,
              position: r.readTable(playlistItems).position,
              track: r.readTableOrNull(tracks),
            ),
          )
          .toList(),
    );
  }

  Future<bool> isFavorite(String fp) async =>
      await (select(favorites)..where(
            (f) => f.trackFp.equals(fp) & f.deleted.equals(false),
          ))
          .getSingleOrNull() !=
      null;

  // check-then-act 必须在事务内:trackFp 是主键,双击红心时两次 toggle 若都读到
  // "未收藏"会双 insert 撞主键崩。软删而非真删:否则取消收藏无法跨设备传播。
  Future<void> toggleFavorite(String fp) => transaction(() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = await (select(
      favorites,
    )..where((f) => f.trackFp.equals(fp))).getSingleOrNull();
    if (row == null) {
      await into(favorites).insert(
        FavoritesCompanion.insert(
          trackFp: fp,
          addedAt: now,
          updatedAt: Value(now),
        ),
      );
      return;
    }
    await (update(favorites)..where((f) => f.trackFp.equals(fp))).write(
      FavoritesCompanion(
        deleted: Value(!row.deleted),
        // 重新收藏时刷新 addedAt,"我喜欢的"按时间倒序才符合直觉
        addedAt: row.deleted ? Value(now) : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  });

  Stream<List<String>> watchFavorites() => (select(favorites)
        ..where((f) => f.deleted.equals(false))
        ..orderBy([(f) => OrderingTerm.desc(f.addedAt)]))
      .watch()
      .map((rows) => rows.map((r) => r.trackFp).toList());

  /// 带显式时间戳的播放记录写入。**`insertOrIgnore` + 自然键唯一索引 = 幂等** ——
  /// 同步取并集时反复写同一条也不会累积重复行。
  Future<void> logPlayEventAt(
    String fp,
    int playedAtMs, {
    String eventType = 'played',
  }) => into(playEvents).insert(
    PlayEventsCompanion.insert(
      trackFp: fp,
      playedAt: playedAtMs,
      eventType: Value(eventType),
    ),
    mode: InsertMode.insertOrIgnore,
  );

  /// 追加式播放日志(只增不改)。M3 同步取并集,永不冲突。
  Future<void> logPlayEvent(String fp) =>
      logPlayEventAt(fp, DateTime.now().millisecondsSinceEpoch);

  /// 供 UI 红心状态实时反映(单曲)。
  Stream<bool> watchIsFavorite(String fp) =>
      (select(favorites)..where(
            (f) => f.trackFp.equals(fp) & f.deleted.equals(false),
          ))
          .watch()
          .map((rows) => rows.isNotEmpty);

  // null 字段必须用 Value.absent()("不改这列");写成 Value(o.title ?? '') 会把列清空。
  Future<void> _materializeOverride(TrackOverride o) =>
      (update(tracks)..where((t) => t.fingerprint.equals(o.trackFp))).write(
        TracksCompanion(
          title: o.title == null ? const Value.absent() : Value(o.title!),
          artist: o.artist == null ? const Value.absent() : Value(o.artist!),
          album: o.album == null ? const Value.absent() : Value(o.album!),
        ),
      );

  /// 写文本修正覆盖层并立即物化回 tracks(tracks 是全 UI 唯一显示源)。
  /// 两步同事务:避免只写一半导致库里显示与覆盖层不一致。
  ///
  /// 传 null/省略 = 不改该项已有修正(合并语义);要清空全部修正用 clearTrackOverride。
  Future<void> setTrackOverride(
    String fp, {
    String? title,
    String? artist,
    String? album,
  }) => transaction(() async {
    await into(trackOverrides).insertOnConflictUpdate(
      TrackOverridesCompanion.insert(
        trackFp: fp,
        title: title == null ? const Value.absent() : Value(title),
        artist: artist == null ? const Value.absent() : Value(artist),
        album: album == null ? const Value.absent() : Value(album),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        // 显式复位:改完修正就不该还是删除态(否则会一直被 getTrackOverride
        // 过滤掉,重新设置的修正等于白设)。
        deleted: const Value(false),
      ),
    );
    final o = await (select(
      trackOverrides,
    )..where((t) => t.trackFp.equals(fp))).getSingle();
    await _materializeOverride(o);
  });

  Future<TrackOverride?> getTrackOverride(String fp) =>
      (select(trackOverrides)..where(
            (t) => t.trackFp.equals(fp) & t.deleted.equals(false),
          ))
          .getSingleOrNull();

  /// 撤销刮削的文本部分。调用侧随后用 applyFileTags 把文件原始标签写回 tracks。
  /// **软删而非真删**:否则这次撤销无法跨设备传播,同步时会被对端旧数据复活。
  Future<void> clearTrackOverride(String fp) =>
      (update(trackOverrides)..where((t) => t.trackFp.equals(fp))).write(
        TrackOverridesCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  /// 把从文件重新读到的原始标签写回 tracks(撤销覆盖后恢复显示)。
  Future<void> applyFileTags(
    String fp, {
    required String title,
    required String artist,
    required String album,
  }) => (update(tracks)..where((t) => t.fingerprint.equals(fp))).write(
    TracksCompanion(
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
    ),
  );

  /// 重扫会把文件原始标签写回 tracks、盖掉文本修正;扫描结束后调用本方法
  /// 重新叠加全部覆盖层。track_overrides 是耐久真相,tracks 是物化视图。
  /// 用 batch:逐条 update 会让每个活跃 watchTracks 流每条重查一次(表级失效),
  /// 与 batchUpsertTracks 同理;batch 亦是单事务,避免中途崩溃只叠加一半。
  Future<void> reapplyAllOverrides() async {
    final all = await (select(
      trackOverrides,
    )..where((t) => t.deleted.equals(false))).get();
    await batch((b) {
      for (final o in all) {
        b.update(
          tracks,
          TracksCompanion(
            title: o.title == null ? const Value.absent() : Value(o.title!),
            artist: o.artist == null ? const Value.absent() : Value(o.artist!),
            album: o.album == null ? const Value.absent() : Value(o.album!),
          ),
          where: (t) => t.fingerprint.equals(o.trackFp),
        );
      }
    });
  }

  /// 首启写入本机身份;已存在则整行不动(deviceId 是跨设备身份,绝不能被改写)。
  ///
  /// **id 必须显式传 0**:id 是 INTEGER 主键,在 SQLite 里即 rowid 别名——
  /// 省略该列时走 rowid 自动分配(1、2、3…),`withDefault(0)` 不生效,
  /// 于是第二次调用不撞主键、insertOrIgnore 无从忽略,会插出第二行身份。
  Future<void> ensureLocalDevice({
    required String deviceId,
    required String deviceName,
  }) => into(localDevice).insert(
    LocalDeviceCompanion.insert(
      id: const Value(0),
      deviceId: deviceId,
      deviceName: deviceName,
    ),
    mode: InsertMode.insertOrIgnore,
  );

  Future<LocalDeviceData?> getLocalDevice() =>
      select(localDevice).getSingleOrNull();

  Future<void> setLocalDeviceName(String name) =>
      (update(localDevice)).write(LocalDeviceCompanion(deviceName: Value(name)));

  Stream<LocalDeviceData?> watchLocalDevice() =>
      select(localDevice).watchSingleOrNull();

  /// 配对成功写入。重复配对更新密钥与名字,但 **pairedAt 保留首次值**
  /// (它是"何时建立信任"的记录,重新协商密钥不改变这一事实)。
  /// 不碰 lastAddress/lastContactAt —— 那两列由 recordPeerContact 负责。
  Future<void> upsertPeer({
    required String deviceId,
    required String deviceName,
    required String platform,
    required String sharedKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(peers).insert(
      PeersCompanion.insert(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: platform,
        sharedKey: sharedKey,
        pairedAt: now,
      ),
      onConflict: DoUpdate(
        (_) => PeersCompanion(
          deviceName: Value(deviceName),
          platform: Value(platform),
          sharedKey: Value(sharedKey),
        ),
      ),
    );
  }

  Future<Peer?> getPeer(String deviceId) =>
      (select(peers)..where((p) => p.deviceId.equals(deviceId)))
          .getSingleOrNull();

  Stream<List<Peer>> watchPeers() =>
      (select(peers)..orderBy([(p) => OrderingTerm.asc(p.deviceName)])).watch();

  /// 只在配对成功与「测试连接」成功时调用(低频)。
  Future<void> recordPeerContact(String deviceId, {required String address}) =>
      (update(peers)..where((p) => p.deviceId.equals(deviceId))).write(
        PeersCompanion(
          lastAddress: Value(address),
          lastContactAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> deletePeer(String deviceId) =>
      (delete(peers)..where((p) => p.deviceId.equals(deviceId))).go();

  /// 读出可同步的全量元数据快照。
  ///
  /// **必须包含已删行**:墓碑是删除得以跨设备传播的唯一载体,过滤掉就等于
  /// 告诉对端"我这儿从来没有过这一项",下一轮它又会被当新增推回来。
  Future<MetadataSnapshot> readSyncSnapshot(String deviceId) async {
    final playlistRows = await select(playlists).get();
    final itemRows = await select(playlistItems).get();
    final favoriteRows = await select(favorites).get();
    final overrideRows = await select(trackOverrides).get();
    final eventRows = await select(playEvents).get();

    return MetadataSnapshot(
      deviceId: deviceId,
      playlists: [
        for (final p in playlistRows)
          PlaylistRow(
            uuid: p.uuid,
            name: p.name,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
            deleted: p.deleted,
          ),
      ],
      playlistItems: [
        for (final i in itemRows)
          PlaylistItemRow(
            playlistUuid: i.playlistUuid,
            trackFp: i.trackFp,
            position: i.position,
            updatedAt: i.updatedAt,
            deleted: i.deleted,
          ),
      ],
      favorites: [
        for (final f in favoriteRows)
          FavoriteRow(
            trackFp: f.trackFp,
            addedAt: f.addedAt,
            updatedAt: f.updatedAt,
            deleted: f.deleted,
          ),
      ],
      overrides: [
        for (final o in overrideRows)
          OverrideRow(
            trackFp: o.trackFp,
            title: o.title,
            artist: o.artist,
            album: o.album,
            updatedAt: o.updatedAt,
            deleted: o.deleted,
          ),
      ],
      playEvents: [
        for (final e in eventRows)
          PlayEventRow(
            trackFp: e.trackFp,
            playedAt: e.playedAt,
            eventType: e.eventType,
          ),
      ],
    );
  }

  /// 把合并结果落库。**单事务** —— 中途失败整体回滚,绝不留半合并状态。
  Future<void> applySyncChanges(MergeResult result) async {
    if (result.isEmpty) return;
    await transaction(() async {
      await batch((b) {
        for (final p in result.playlists) {
          b.insert(
            playlists,
            PlaylistsCompanion.insert(
              uuid: p.uuid,
              name: p.name,
              createdAt: p.createdAt,
              updatedAt: p.updatedAt,
              deleted: Value(p.deleted),
            ),
            onConflict: DoUpdate(
              (_) => PlaylistsCompanion(
                name: Value(p.name),
                updatedAt: Value(p.updatedAt),
                deleted: Value(p.deleted),
              ),
            ),
          );
        }
        for (final i in result.playlistItems) {
          b.insert(
            playlistItems,
            PlaylistItemsCompanion.insert(
              playlistUuid: i.playlistUuid,
              trackFp: i.trackFp,
              position: i.position,
              updatedAt: Value(i.updatedAt),
              deleted: Value(i.deleted),
            ),
            // playlist_items 的主键是隐式 rowid,冲突目标必须显式写成唯一键,
            // 否则 upsert 认不出"同一项"而去插新行、撞唯一约束。
            onConflict: DoUpdate(
              (_) => PlaylistItemsCompanion(
                position: Value(i.position),
                updatedAt: Value(i.updatedAt),
                deleted: Value(i.deleted),
              ),
              target: [playlistItems.playlistUuid, playlistItems.trackFp],
            ),
          );
        }
        for (final f in result.favorites) {
          b.insert(
            favorites,
            FavoritesCompanion.insert(
              trackFp: f.trackFp,
              addedAt: f.addedAt,
              updatedAt: Value(f.updatedAt),
              deleted: Value(f.deleted),
            ),
            onConflict: DoUpdate(
              (_) => FavoritesCompanion(
                addedAt: Value(f.addedAt),
                updatedAt: Value(f.updatedAt),
                deleted: Value(f.deleted),
              ),
            ),
          );
        }
        for (final o in result.overrides) {
          b.insert(
            trackOverrides,
            TrackOverridesCompanion.insert(
              trackFp: o.trackFp,
              title: Value(o.title),
              artist: Value(o.artist),
              album: Value(o.album),
              updatedAt: o.updatedAt,
              deleted: Value(o.deleted),
            ),
            onConflict: DoUpdate(
              (_) => TrackOverridesCompanion(
                title: Value(o.title),
                artist: Value(o.artist),
                album: Value(o.album),
                updatedAt: Value(o.updatedAt),
                deleted: Value(o.deleted),
              ),
            ),
          );
        }
        for (final e in result.playEvents) {
          b.insert(
            playEvents,
            PlayEventsCompanion.insert(
              trackFp: e.trackFp,
              playedAt: e.playedAt,
              eventType: Value(e.eventType),
            ),
            mode: InsertMode.insertOrIgnore, // 自然键唯一索引兜底,幂等
          );
        }
      });

      // 文本修正变了就物化回 tracks,否则同步过来的标题在 UI 上看不到。
      // reapplyAllOverrides 内部是 batch(单次流失效),不会引发风暴。
      if (result.overrides.isNotEmpty) {
        await reapplyAllOverrides();
      }
    });
  }
}
