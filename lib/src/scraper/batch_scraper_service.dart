import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/database.dart';
import 'metadata_source.dart';
import 'scraper_service.dart';

/// 一次批量刮削的进度快照。finished=true 为收尾事件(带最终计数)。
class BatchProgress {
  const BatchProgress({
    required this.done,
    required this.total,
    this.currentTitle,
    required this.appliedCovers,
    required this.appliedLyrics,
    required this.skippedNoMatch,
    required this.finished,
  });

  final int done; // 已处理曲目数
  final int total; // 待处理(缺封面或缺歌词)曲目总数
  final String? currentTitle;
  final int appliedCovers;
  final int appliedLyrics;
  final int skippedNoMatch; // 搜到但无可信封面且无歌词,或搜索失败
  final bool finished;
}

/// 对"缺封面/缺歌词"的曲目批量自动补全伴随文件。复用 M2-B ScraperService。
/// 只写 .jpg/.lrc,不改音频字节、不动文本修正(applyText 恒 false)。
class BatchScraperService {
  BatchScraperService(this.scraper);

  final ScraperService scraper;

  bool _has(String audioPath, List<String> exts) =>
      exts.any((e) => File(p.setExtension(audioPath, e)).existsSync());

  bool _hasCover(String audioPath) => _has(audioPath, const ['.jpg', '.png']);
  bool _hasLyrics(String audioPath) => _has(audioPath, const ['.lrc']);

  /// 顺序处理(单曲内三源已并行;MusicBrainz 源自带 1req/s 限流,顺序调用自动受限)。
  /// 每首处理后发一次进度;shouldCancel 在每首前检查,已补的保留。
  Stream<BatchProgress> run(
    List<Track> tracks, {
    bool Function()? shouldCancel,
  }) async* {
    // 先筛缺项,记住每首缺什么(避免覆盖已有 sidecar)。
    final targets = <Track>[];
    final needCover = <bool>[];
    final needLyrics = <bool>[];
    for (final t in tracks) {
      final nc = !_hasCover(t.path);
      final nl = !_hasLyrics(t.path);
      if (nc || nl) {
        targets.add(t);
        needCover.add(nc);
        needLyrics.add(nl);
      }
    }
    final total = targets.length;
    var done = 0, covers = 0, lyricsN = 0, skipped = 0;

    if (total == 0) {
      yield const BatchProgress(
        done: 0,
        total: 0,
        appliedCovers: 0,
        appliedLyrics: 0,
        skippedNoMatch: 0,
        finished: true,
      );
      return;
    }

    for (var i = 0; i < targets.length; i++) {
      if (shouldCancel?.call() ?? false) break;
      final t = targets[i];
      var appliedSomething = false;
      try {
        final q = TrackQuery(
          title: t.title,
          artist: t.artist,
          album: t.album,
          durationMs: t.durationMs,
        );
        final res = await scraper.search(q);
        final best = res.matches.isNotEmpty ? res.matches.first : null;
        final wantCover =
            needCover[i] &&
            best != null &&
            best.coverUrl != null &&
            isConfidentMatch(q, best);
        LyricsCandidate? bestLyrics;
        if (needLyrics[i]) {
          for (final c in res.lyrics) {
            if (c.best != null) {
              bestLyrics = c;
              break;
            }
          }
        }
        // 封面与歌词各自独立应用:一方失败(如封面下载出错)不连累另一方,
        // 计数按实际写入。
        if (wantCover) {
          try {
            await scraper.apply(
              t,
              ScrapeSelection(match: best, applyCover: true, applyText: false),
            );
            covers++;
            appliedSomething = true;
          } catch (_) {}
        }
        if (bestLyrics != null) {
          try {
            await scraper.apply(
              t,
              ScrapeSelection(applyText: false, lyrics: bestLyrics),
            );
            lyricsN++;
            appliedSomething = true;
          } catch (_) {}
        }
      } catch (_) {
        // 搜索/下载失败:隔离,该首跳过。
      }
      if (!appliedSomething) skipped++;
      done++;
      yield BatchProgress(
        done: done,
        total: total,
        currentTitle: t.title,
        appliedCovers: covers,
        appliedLyrics: lyricsN,
        skippedNoMatch: skipped,
        finished: false,
      );
    }

    yield BatchProgress(
      done: done,
      total: total,
      appliedCovers: covers,
      appliedLyrics: lyricsN,
      skippedNoMatch: skipped,
      finished: true,
    );
  }
}
