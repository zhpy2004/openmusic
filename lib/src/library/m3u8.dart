import 'package:path/path.dart' as p;

/// 导出一条曲目所需的最小信息。IO 由调用侧负责,本文件全是纯函数,便于单测。
class M3u8Entry {
  const M3u8Entry({
    required this.absPath,
    required this.artist,
    required this.title,
    required this.durationSec,
  });

  final String absPath;
  final String artist;
  final String title;
  final int durationSec;
}

/// 歌单 → 标准 M3U8 文本。路径相对 [baseDir](.m3u8 将保存的目录),统一正斜杠
/// ——M3U8 标准语义就是"相对于播放列表文件自身位置",别的播放器也这么解析。
String serializeM3u8({
  required String baseDir,
  required List<M3u8Entry> entries,
}) {
  final buf = StringBuffer('#EXTM3U\n');
  for (final e in entries) {
    final raw = e.artist.isEmpty ? e.title : '${e.artist} - ${e.title}';
    // 标签里若混入 CR/LF(损坏元数据)会往 .m3u8 注入多余行,压成空格。
    final label = raw.replaceAll(RegExp(r'[\r\n]+'), ' ');
    buf.writeln('#EXTINF:${e.durationSec},$label');
    final rel = p.relative(e.absPath, from: baseDir).replaceAll(r'\', '/');
    buf.writeln(rel);
  }
  return buf.toString();
}

class ParsedM3u8 {
  const ParsedM3u8(this.paths);

  /// 绝对路径,正斜杠归一(便于与曲库路径比较)。
  final List<String> paths;
}

/// 解析 M3U8:忽略空行与 `#` 开头行;路径相对 [baseDir] 解析成绝对,统一正斜杠。
ParsedM3u8 parseM3u8({required String text, required String baseDir}) {
  final paths = <String>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final abs = p.normalize(p.join(baseDir, line)).replaceAll(r'\', '/');
    paths.add(abs);
  }
  return ParsedM3u8(paths);
}

class MatchResult {
  const MatchResult({required this.matchedFps, required this.unmatched});

  final List<String> matchedFps;
  final int unmatched;
}

/// 按曲库"绝对路径→指纹"表匹配;未命中计数。两侧路径都应正斜杠归一后比较。
/// M3U8 里没有指纹,只能按路径匹配——跨机器的 M3U8 大多匹配不上是预期行为,
/// 真正的跨设备歌单靠 M3 同步(按指纹)。
///
/// [caseInsensitive]:Windows 文件系统大小写不敏感,手写/外部 m3u8 的盘符或
/// 路径段大小写可能与曲库存的字符串不同(`c:/music` vs `C:/Music`),会误判未匹配。
/// 调用侧在 Windows 上传 `Platform.isWindows` 打开大小写折叠比较。
MatchResult matchPaths({
  required List<String> paths,
  required Map<String, String> libraryPathToFp,
  bool caseInsensitive = false,
}) {
  final lib = caseInsensitive
      ? {for (final e in libraryPathToFp.entries) e.key.toLowerCase(): e.value}
      : libraryPathToFp;
  final matched = <String>[];
  var miss = 0;
  for (final path in paths) {
    final fp = lib[caseInsensitive ? path.toLowerCase() : path];
    if (fp != null) {
      matched.add(fp);
    } else {
      miss++;
    }
  }
  return MatchResult(matchedFps: matched, unmatched: miss);
}
