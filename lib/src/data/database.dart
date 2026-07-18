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

@DriftDatabase(tables: [Tracks, ScanRoots])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  // insertOnConflictUpdate 默认只按主键（id）判定冲突；path 是单独的唯一约束，
  // 必须显式指定 conflict target，否则同 path 二次写入会因主键不冲突而尝试
  // 插入新行，进而撞上 path 的 UNIQUE 约束报错。
  Future<void> upsertTrack(TracksCompanion entry) => into(tracks).insert(
        entry,
        onConflict: DoUpdate((_) => entry, target: [tracks.path]),
      );

  /// 批量 upsert：单事务、单次流通知。扫描器逐文件 await upsertTrack 会让
  /// 每个活跃 watchTracks 流每文件全量重查一次（表级失效，万级文件 O(n²)），
  /// 且逐条隐式事务逐条 journal commit——批量把两者都收敛到每批一次。
  Future<void> batchUpsertTracks(List<TracksCompanion> entries) =>
      batch((b) {
        for (final e in entries) {
          b.insert(tracks, e,
              onConflict: DoUpdate((_) => e, target: [tracks.path]));
        }
      });

  Stream<List<Track>> watchTracks(String query) {
    // NOCASE：BINARY collation 会把所有大写排到所有小写之前
    //（[apple, Zebra, Banana] → [Banana, Zebra, apple]）。
    final q = select(tracks)
      ..orderBy([(t) => OrderingTerm(expression: t.title.collate(Collate.noCase))]);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim()}%';
      q.where((t) =>
          t.title.like(like) | t.artist.like(like) | t.album.like(like));
    }
    return q.watch();
  }

  /// 增量扫描用：path → (mtimeMs, sizeBytes)
  Future<Map<String, ({int mtimeMs, int sizeBytes})>> pathIndex() async {
    final rows = await (selectOnly(tracks)
          ..addColumns([tracks.path, tracks.mtimeMs, tracks.sizeBytes]))
        .get();
    return {
      for (final r in rows)
        r.read(tracks.path)!: (
          mtimeMs: r.read(tracks.mtimeMs)!,
          sizeBytes: r.read(tracks.sizeBytes)!
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
              i, i + 500 > toDelete.length ? toDelete.length : i + 500);
          await (delete(tracks)..where((t) => t.path.isIn(chunk))).go();
        }
      });

  Future<void> addScanRoot(String path) => into(scanRoots)
      .insert(ScanRootsCompanion.insert(path: path), mode: InsertMode.insertOrIgnore);

  Future<void> removeScanRoot(String path) =>
      (delete(scanRoots)..where((r) => r.path.equals(path))).go();

  Stream<List<String>> watchScanRoots() =>
      select(scanRoots).watch().map((rows) => rows.map((r) => r.path).toList());
}
