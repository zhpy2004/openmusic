import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/database.dart';
import 'metadata_source.dart';

/// 一次刮削搜索的结果。failedSources 让 UI 能提示"某源暂不可用",
/// 而不是把整次搜索判为失败(母 spec §8:单点失败不中断整体)。
class ScrapeResults {
  const ScrapeResults({
    required this.matches,
    required this.lyrics,
    required this.failedSources,
  });

  final List<MatchCandidate> matches;
  final List<LyricsCandidate> lyrics;
  final List<String> failedSources;

  bool get isEmpty => matches.isEmpty && lyrics.isEmpty;
}

/// 用户在刮削页做出的选择。match 可只用封面或只用文本(两个开关独立)。
class ScrapeSelection {
  const ScrapeSelection({
    this.match,
    this.applyCover = false,
    this.applyText = false,
    this.lyrics,
  });

  final MatchCandidate? match;
  final bool applyCover;
  final bool applyText;
  final LyricsCandidate? lyrics;
}

class ScraperService {
  ScraperService({
    required this.matchSources,
    required this.lyricsSources,
    this.db,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final List<MetadataSource> matchSources;
  final List<LyricsSource> lyricsSources;
  final AppDatabase? db;
  final http.Client _http;

  /// 伴随文件路径:与音频同名换扩展名。逐曲一份,混排目录也不会串封面。
  static String coverPathFor(String audioPath) =>
      p.setExtension(audioPath, '.jpg');
  static String lyricsPathFor(String audioPath) =>
      p.setExtension(audioPath, '.lrc');

  /// 并行查所有源;任一源抛异常只记名、不影响其余(失败隔离)。
  Future<ScrapeResults> search(TrackQuery q) async {
    final matches = <MatchCandidate>[];
    final lyrics = <LyricsCandidate>[];
    final failed = <String>[];

    Future<void> runMatch(MetadataSource s) async {
      try {
        matches.addAll(await s.searchMatches(q));
      } catch (_) {
        failed.add(s.name);
      }
    }

    Future<void> runLyrics(LyricsSource s) async {
      try {
        lyrics.addAll(await s.searchLyrics(q));
      } catch (_) {
        failed.add(s.name);
      }
    }

    await Future.wait([
      for (final s in matchSources) runMatch(s),
      for (final s in lyricsSources) runLyrics(s),
    ]);

    return ScrapeResults(
      matches: rankMatches(q, matches),
      lyrics: lyrics,
      failedSources: failed,
    );
  }

  /// 应用用户选择。**绝不修改音频文件字节**——封面/歌词写同名伴随文件,
  /// 文本修正写覆盖表。这是 M2-B 的红线:动了音频字节指纹就变,
  /// 歌单/收藏关联会断、M3 同步会把同一首歌当成两首。
  Future<void> apply(Track track, ScrapeSelection sel) async {
    final m = sel.match;

    if (sel.applyCover && m?.coverUrl != null) {
      final res = await _http.get(Uri.parse(m!.coverUrl!));
      if (res.statusCode != 200) {
        throw Exception('封面下载失败 HTTP ${res.statusCode}');
      }
      await File(coverPathFor(track.path)).writeAsBytes(res.bodyBytes);
    }

    final lrc = sel.lyrics?.best;
    if (lrc != null) {
      await File(lyricsPathFor(track.path)).writeAsString(lrc);
    }

    if (sel.applyText && m != null) {
      await db?.setTrackOverride(
        track.fingerprint,
        title: m.title.isEmpty ? null : m.title,
        artist: m.artist.isEmpty ? null : m.artist,
        album: m.album.isEmpty ? null : m.album,
      );
    }
  }

  /// 撤销刮削:删伴随文件 + 删覆盖行,并把调用方从文件重新读到的原始标签
  /// 写回 tracks(文件即真相)。幂等:文件/覆盖行不存在时静默跳过。
  ///
  /// ⚠️ 已知隐患(M2-B 未挂 UI 入口,接线前必须先解决):本方法**无条件**删除同名
  /// .jpg/.lrc,但并不知道这两个文件是不是刮削写的。用户自己手工放的封面/手写的
  /// 歌词会被一并删掉——违反母 spec §8「任何操作不静默丢数据」。挂 UI 撤销按钮前
  /// 需先记录 sidecar 来源(如刮削时在 override 行留标记),只删刮削自己写的那份。
  Future<void> undo(
    Track track, {
    required String fileTitle,
    required String fileArtist,
    required String fileAlbum,
  }) async {
    for (final path in [coverPathFor(track.path), lyricsPathFor(track.path)]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    await db?.clearTrackOverride(track.fingerprint);
    await db?.applyFileTags(
      track.fingerprint,
      title: fileTitle,
      artist: fileArtist,
      album: fileAlbum,
    );
  }
}
