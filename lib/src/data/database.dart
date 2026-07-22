import 'dart:math';

import 'package:drift/drift.dart';

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

  @override
  Set<Column> get primaryKey => {uuid};
}

class PlaylistItems extends Table {
  TextColumn get playlistUuid => text()();
  TextColumn get trackFp => text()(); // 内容指纹引用,非 tracks.id
  IntColumn get position => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {playlistUuid, trackFp},
  ];
}

class Favorites extends Table {
  TextColumn get trackFp => text()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {trackFp};
}

class PlayEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get trackFp => text()();
  IntColumn get playedAt => integer()();
  TextColumn get eventType => text().withDefault(const Constant('played'))();
}

/// 歌单成员 + 关联曲目(可能为 null=文件缺失/未扫描到)。
class PlaylistEntry {
  const PlaylistEntry({required this.fp, required this.position, this.track});
  final String fp;
  final int position;
  final Track? track;
}

@DriftDatabase(
  tables: [Tracks, ScanRoots, Playlists, PlaylistItems, Favorites, PlayEvents],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  final _rnd = Random();

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v1→v2:只新建 M2-A 的四张表,现有 tracks/scan_roots 原样保留。
      if (from < 2) {
        await m.createTable(playlists);
        await m.createTable(playlistItems);
        await m.createTable(favorites);
        await m.createTable(playEvents);
      }
    },
  );

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

  Future<void> deletePlaylist(String uuid) => transaction(() async {
    await (delete(
      playlistItems,
    )..where((i) => i.playlistUuid.equals(uuid))).go();
    await (delete(playlists)..where((p) => p.uuid.equals(uuid))).go();
  });

  Stream<List<Playlist>> watchPlaylists() => (select(
    playlists,
  )..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])).watch();

  Future<void> _bumpPlaylist(String uuid) =>
      (update(playlists)..where((p) => p.uuid.equals(uuid))).write(
        PlaylistsCompanion(
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> addToPlaylist(String uuid, String fp) => transaction(() async {
    // 重复添加 = 完全 no-op:不插入、不 bump updatedAt。否则重复 add 会让
    // 歌单假装"被改过"跳到列表顶,且 M3 LWW 会拿一个未变化的歌单覆盖对端真实改动。
    final exists =
        await (select(
              playlistItems,
            )..where((i) => i.playlistUuid.equals(uuid) & i.trackFp.equals(fp)))
            .getSingleOrNull();
    if (exists != null) return; // 已在歌单:no-op
    final maxPos =
        await (selectOnly(playlistItems)
              ..addColumns([playlistItems.position.max()])
              ..where(playlistItems.playlistUuid.equals(uuid)))
            .map((r) => r.read(playlistItems.position.max()))
            .getSingleOrNull();
    await into(playlistItems).insert(
      PlaylistItemsCompanion.insert(
        playlistUuid: uuid,
        trackFp: fp,
        position: (maxPos ?? -1) + 1,
      ),
    );
    await _bumpPlaylist(uuid);
  });

  Future<void> removeFromPlaylist(String uuid, String fp) => transaction(
    () async {
      await (delete(
        playlistItems,
      )..where((i) => i.playlistUuid.equals(uuid) & i.trackFp.equals(fp))).go();
      await _bumpPlaylist(uuid);
    },
  );

  /// 重排:[fpsInOrder] 必须是该歌单**当前全部成员**的完整期望顺序。
  /// 传子集会让未列出的项保留旧 position → 可能出现重复 position(排序不稳:
  /// watchPlaylistItems 的 ORDER BY position 在重复值上顺序未定义)。
  /// UI(ReorderableListView)总传全量顺序,满足此前提。
  Future<void> reorderPlaylist(String uuid, List<String> fpsInOrder) =>
      transaction(() async {
        for (var i = 0; i < fpsInOrder.length; i++) {
          await (update(playlistItems)..where(
                (it) =>
                    it.playlistUuid.equals(uuid) &
                    it.trackFp.equals(fpsInOrder[i]),
              ))
              .write(PlaylistItemsCompanion(position: Value(i)));
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
          ..where(playlistItems.playlistUuid.equals(uuid))
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
      await (select(
        favorites,
      )..where((f) => f.trackFp.equals(fp))).getSingleOrNull() !=
      null;

  // check-then-act 必须在事务内:trackFp 是主键,双击红心时两次 toggle 若都读到
  // "未收藏"会双 insert 撞主键崩(与 addToPlaylist 同款防护)。
  Future<void> toggleFavorite(String fp) => transaction(() async {
    if (await isFavorite(fp)) {
      await (delete(favorites)..where((f) => f.trackFp.equals(fp))).go();
    } else {
      await into(favorites).insert(
        FavoritesCompanion.insert(
          trackFp: fp,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
  });

  Stream<List<String>> watchFavorites() =>
      (select(favorites)..orderBy([(f) => OrderingTerm.desc(f.addedAt)]))
          .watch()
          .map((rows) => rows.map((r) => r.trackFp).toList());

  /// 追加式播放日志(只增不改)。M3 同步取并集,永不冲突。
  Future<void> logPlayEvent(String fp) => into(playEvents).insert(
    PlayEventsCompanion.insert(
      trackFp: fp,
      playedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  /// 供 UI 红心状态实时反映(单曲)。
  Stream<bool> watchIsFavorite(String fp) => (select(
    favorites,
  )..where((f) => f.trackFp.equals(fp))).watch().map((rows) => rows.isNotEmpty);
}
