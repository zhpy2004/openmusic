/// 刮削源的输入:取自曲目当前(可能不准的)标签。
class TrackQuery {
  const TrackQuery({
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
  });

  final String title;
  final String artist;
  final String album;

  /// 供 LRCLIB 按时长消歧;0 = 未知,源可忽略。
  final int durationMs;
}

/// 一条"发行版匹配"候选:封面与文本捆绑(iTunes/MusicBrainz 天然如此)。
class MatchCandidate {
  const MatchCandidate({
    required this.source,
    required this.title,
    required this.artist,
    required this.album,
    this.year,
    this.coverUrl,
  });

  final String source; // 来源徽标
  final String title;
  final String artist;
  final String album;
  final int? year;
  final String? coverUrl;
}

/// 一条歌词候选(LRCLIB 是曲目级、与封面/文本无关,故独立)。
class LyricsCandidate {
  const LyricsCandidate({
    required this.source,
    required this.title,
    required this.artist,
    this.syncedLrc,
    this.plainLrc,
  });

  final String source;
  final String title;
  final String artist;
  final String? syncedLrc; // 带 [mm:ss.xx] 时间轴
  final String? plainLrc;

  bool get hasSynced => (syncedLrc ?? '').isNotEmpty;

  /// 优先写带时间轴的;没有则退回纯文本。两者都空 = 这条候选没歌词。
  String? get best =>
      hasSynced ? syncedLrc : (plainLrc?.isNotEmpty == true ? plainLrc : null);
}

/// 提供"封面 + 文本"候选的源(iTunes、MusicBrainz)。
abstract class MetadataSource {
  String get name;
  Future<List<MatchCandidate>> searchMatches(TrackQuery q);
}

/// 提供歌词候选的源(LRCLIB)。
abstract class LyricsSource {
  String get name;
  Future<List<LyricsCandidate>> searchLyrics(TrackQuery q);
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s\-_/()\[\]]'), '');

/// 极简相似度:归一化后互相包含即高分,否则按公共字符比例。够用于候选排序,
/// 不追求准确率——最终由用户点选,排序只是把"看起来最像的"顶上去。
double _similarity(String a, String b) {
  final x = _norm(a), y = _norm(b);
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  if (x.contains(y) || y.contains(x)) return 0.8;
  final setY = y.split('').toSet();
  final common = x.split('').where(setY.contains).length;
  return common / (x.length > y.length ? x.length : y.length);
}

/// 按"与原曲目标题/歌手的相似度"降序;同分时有封面的排前。不做自动选中。
List<MatchCandidate> rankMatches(TrackQuery q, List<MatchCandidate> items) {
  double score(MatchCandidate c) =>
      _similarity(q.title, c.title) * 2 +
      _similarity(q.artist, c.artist) +
      (c.coverUrl != null ? 0.1 : 0);
  final out = List<MatchCandidate>.of(items);
  out.sort((a, b) => score(b).compareTo(score(a)));
  return out;
}
