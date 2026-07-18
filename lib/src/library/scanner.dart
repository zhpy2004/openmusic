import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import 'fingerprint.dart';
import 'tag_reader.dart';

const audioExtensions = {
  '.mp3',
  '.flac',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.wav',
};

class ScanProgress {
  const ScanProgress({
    required this.scanned,
    required this.total,
    this.currentPath,
    this.problems = const [],
    this.done = false,
  });

  final int scanned;
  final int total;
  final String? currentPath;
  final List<String> problems; // 损坏/读取失败的文件（spec §8）
  final bool done;
}

class LibraryScanner {
  LibraryScanner(
    this._db,
    this._tagReader, {
    this._fingerprint = computeFileFingerprint,
  });

  final AppDatabase _db;
  final TagReader _tagReader;
  final Future<String> Function(File) _fingerprint;

  Stream<ScanProgress> scan(List<String> roots) async* {
    // 1. 收集候选文件（去重：重叠 root——如 /music 与 /music/sub 同时在列——
    //    会让同一文件出现两次，导致双倍 tag 读+指纹和虚高的 total）
    final files = <File>[];
    final seen = <String>{};
    final problems = <String>[]; // 提前声明：不可达根的提示也要记进来
    // existsSync() 为 false 的根（如 NAS/SD 卡离线）：不能当作"用户已移除
    // 该根"处理——下方 deleteTracksNotIn 是"文件即真相"式全量清理，若不
    // 把这些根排除在外，会把该根下所有已入库曲目当成"文件已消失"整棵删掉。
    // 这里存 dir.path（已做过分隔符归一）而非原始 root 字符串，因为下面
    // 子树判定要跟同样来自 Directory 归一化路径的场景对齐。
    final unreachableRootDirs = <String>[];
    for (final root in roots) {
      // Windows 下统一分隔符：'/music/sub' 与 '\music\sub' 列出的 entity.path
      // 前缀会带各自的写法，字符串去重要求先归一。
      final dir = Directory(
        Platform.isWindows ? root.replaceAll('/', r'\') : root,
      );
      if (!dir.existsSync()) {
        unreachableRootDirs.add(dir.path);
        problems.add('根目录不可达: $root(本轮不清理其下曲目)');
        continue;
      }
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final dot = entity.path.lastIndexOf('.');
        if (dot < 0) continue;
        final ext = entity.path.substring(dot).toLowerCase();
        if (!audioExtensions.contains(ext)) continue;
        if (seen.add(entity.path)) files.add(entity);
      }
    }

    final known = await _db.pathIndex();
    final pending = <TracksCompanion>[]; // 批量缓冲：见 batchUpsertTracks 注释
    var scanned = 0;

    for (final file in files) {
      scanned++;
      try {
        // stat 也在 try 内：文件在收集与处理之间被删/失去权限时（竞态），
        // statSync 抛错应记入 problems，而不是写出 size:-1/mtime:0 的幽灵行。
        final stat = file.statSync();
        final mtimeMs = stat.modified.millisecondsSinceEpoch;
        final prev = known[file.path];
        final unchanged =
            prev != null &&
            prev.mtimeMs == mtimeMs &&
            prev.sizeBytes == stat.size;
        if (!unchanged) {
          final meta = await _tagReader.read(file.path);
          final fp = await _fingerprint(file);
          pending.add(
            TracksCompanion.insert(
              path: file.path,
              fingerprint: fp,
              title: meta.title,
              artist: Value(meta.artist),
              album: Value(meta.album),
              albumArtist: Value(meta.albumArtist),
              durationMs: Value(meta.durationMs),
              trackNumber: Value(meta.trackNumber),
              year: Value(meta.year),
              sizeBytes: stat.size,
              mtimeMs: mtimeMs,
            ),
          );
        }
        // unchanged 则跳过重读（增量扫描，spec §3.1），但仍走下方的
        // 周期上报+让出——1 万文件增量重扫若全程无 await/yield，
        // 会是主 isolate 一整段阻塞且进度流无事件。
      } catch (e) {
        problems.add('${file.path}: $e'); // 单文件失败不中断（spec §8）
      }
      // 批量 flush 放在单文件 try 之外：批失败是批级问题，不能记在
      // 当前文件头上，也不能把失败批留在缓冲里反复重试
      if (pending.length >= 200) {
        await _flush(pending, problems);
      }
      // 进度节流：处理与跳过共用同一计数，每 200 个文件上报一次并让出
      // 事件循环（skip 路径全同步，不让出会冻结 UI）。
      if (scanned % 200 == 0) {
        yield ScanProgress(
          scanned: scanned,
          total: files.length,
          currentPath: file.path,
          problems: problems,
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (pending.isNotEmpty) {
      await _flush(pending, problems);
    }

    // 2. 清理：文件已不存在的行删掉（文件即真相）——但不可达根下的已知
    // 路径要并入 keep 集，本轮不清理（见上方 unreachableRootDirs 注释）。
    final keep = files.map((f) => f.path).toSet();
    if (unreachableRootDirs.isNotEmpty) {
      // 子树判定用 package:path 而非裸 startsWith：分隔符（'/'  vs '\'）和
      // 前缀边界（'/music' 不该错误吞掉 '/music2/x'）都是 startsWith 的坑。
      // Windows 下 p.isWithin/p.equals 走 WindowsStyle：
      // codeUnitsEqual 折叠 ASCII 大小写、'/' 与 '\' 视为等价分隔符
      // （package:path 1.9.1 lib/src/style/windows.dart 第 144-158 行），
      // canonicalizePart 也做 toLowerCase（同文件第 181 行）——因此本身就
      // 大小写不敏感，无需再手工 fold。两侧路径本就同源于入库路径，理论
      // 同 case，这里的不敏感只是防御性保底。
      for (final knownPath in known.keys) {
        final underUnreachableRoot = unreachableRootDirs.any(
          (root) => p.isWithin(root, knownPath) || p.equals(root, knownPath),
        );
        if (underUnreachableRoot) keep.add(knownPath);
      }
    }
    await _db.deleteTracksNotIn(keep);
    yield ScanProgress(
      scanned: files.length,
      total: files.length,
      problems: problems,
      done: true,
    );
  }

  Future<void> _flush(
    List<TracksCompanion> pending,
    List<String> problems,
  ) async {
    try {
      await _db.batchUpsertTracks(List.of(pending));
    } catch (e) {
      problems.add('批量写入失败（${pending.length} 条）: $e');
    } finally {
      pending.clear(); // 无论成败都清空，失败批不重试（下次扫描会重新发现）
    }
  }
}
