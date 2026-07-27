/// 一行歌词:开始时间 + 文本。纯文本兜底时 time 统一为 Duration.zero。
class LrcLine {
  final Duration time;
  final String text;
  const LrcLine(this.time, this.text);
}

/// 解析后的歌词。synced 为真时 lines 按 time 升序;纯文本时保留原顺序。
class Lyrics {
  final List<LrcLine> lines;
  final bool synced;
  const Lyrics(this.lines, this.synced);
  bool get isEmpty => lines.isEmpty;
}

// 时间戳 [mm:ss]、[mm:ss.xx]、[mm:ss.xxx](分隔符接受 . 或 :)。
final _tagRe = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{2,3}))?\]');
final _offsetRe = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
final _metaRe = RegExp(r'^\[[a-zA-Z]+:.*\]$');

/// 解析 LRC 文本。永不抛异常(容错):无法解析的内容降级或跳过。
Lyrics parseLrc(String raw) {
  int offsetMs = 0;
  final om = _offsetRe.firstMatch(raw);
  if (om != null) offsetMs = int.tryParse(om.group(1)!) ?? 0;

  final timed = <LrcLine>[];
  bool anyTimed = false;

  for (final rawLine in raw.split('\n')) {
    final line = rawLine.trimRight();
    final matches = _tagRe.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.substring(matches.last.end).trim();
    if (text.isEmpty) continue; // 跳过纯空文本行(纯元数据、空歌词)
    anyTimed = true;
    for (final m in matches) {
      final mm = int.parse(m.group(1)!);
      final ss = int.parse(m.group(2)!);
      final frac = m.group(3);
      int ms = 0;
      if (frac != null) {
        ms = frac.length == 2 ? int.parse(frac) * 10 : int.parse(frac);
      }
      var t =
          Duration(minutes: mm, seconds: ss, milliseconds: ms).inMilliseconds -
          offsetMs;
      if (t < 0) t = 0;
      timed.add(LrcLine(Duration(milliseconds: t), text));
    }
  }

  if (anyTimed) {
    timed.sort((a, b) => a.time.compareTo(b.time));
    return Lyrics(timed, true);
  }

  // 纯文本兜底:无任何时间戳。逐非空行,跳过元数据行,保留顺序。
  final plain = <LrcLine>[];
  for (final rawLine in raw.split('\n')) {
    final t = rawLine.trim();
    if (t.isEmpty) continue;
    if (_metaRe.hasMatch(t)) continue;
    plain.add(LrcLine(Duration.zero, t));
  }
  return Lyrics(plain, false);
}

/// 二分查找 pos 时刻应高亮的行下标:time <= pos 的最后一行。
/// pos 早于首行时返回 0(clamp);lines 为空返回 0。仅对 synced 有意义。
int currentIndexAt(List<LrcLine> lines, Duration pos) {
  if (lines.isEmpty) return 0;
  int lo = 0, hi = lines.length - 1, ans = 0;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time <= pos) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}
