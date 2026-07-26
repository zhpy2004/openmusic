import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/lyrics/lrc.dart';

void main() {
  test('synced:两位毫秒(厘秒)按 *10 解析,按时间排序', () {
    final r = parseLrc('[00:12.50]hello\n[00:01.00]first');
    expect(r.synced, true);
    expect(r.lines.map((l) => l.text).toList(), ['first', 'hello']);
    expect(r.lines[0].time, const Duration(seconds: 1));
    expect(r.lines[1].time, const Duration(seconds: 12, milliseconds: 500));
  });

  test('synced:三位毫秒原样解析', () {
    final r = parseLrc('[01:02.345]x');
    expect(r.lines.single.time,
        const Duration(minutes: 1, seconds: 2, milliseconds: 345));
  });

  test('synced:无毫秒也接受', () {
    final r = parseLrc('[00:05]x');
    expect(r.lines.single.time, const Duration(seconds: 5));
  });

  test('一行多时间戳展开成多条,文本相同', () {
    final r = parseLrc('[00:10.00][01:00.00]副歌');
    expect(r.lines.length, 2);
    expect(r.lines.every((l) => l.text == '副歌'), true);
    expect(r.lines[0].time, const Duration(seconds: 10));
    expect(r.lines[1].time, const Duration(minutes: 1));
  });

  test('元数据标签与空文本行被跳过', () {
    final r = parseLrc('[ti:Title]\n[ar:Artist]\n[00:03.00]\n[00:04.00]real');
    expect(r.synced, true);
    expect(r.lines.map((l) => l.text).toList(), ['real']);
  });

  test('offset 正值使歌词提前(时间减 offset),clamp 到 >=0', () {
    final r = parseLrc('[offset:500]\n[00:00.20]a\n[00:02.00]b');
    // a: 200ms - 500ms => clamp 0;b: 2000-500=1500
    expect(r.lines[0].time, Duration.zero);
    expect(r.lines[1].time, const Duration(milliseconds: 1500));
  });

  test('无任何时间戳 => 纯文本兜底 synced=false,保留原顺序,跳过元数据/空行', () {
    final r = parseLrc('[ti:X]\n第一行\n\n第二行');
    expect(r.synced, false);
    expect(r.lines.map((l) => l.text).toList(), ['第一行', '第二行']);
    expect(r.lines.every((l) => l.time == Duration.zero), true);
  });

  test('空输入 => 空 Lyrics', () {
    final r = parseLrc('');
    expect(r.isEmpty, true);
  });

  test('CRLF 行尾不残留 \\r', () {
    final r = parseLrc('[00:01.00]a\r\n[00:02.00]b\r\n');
    expect(r.lines.map((l) => l.text).toList(), ['a', 'b']);
  });

  group('currentIndexAt', () {
    final lines = [
      const LrcLine(Duration(seconds: 0), 'a'),
      const LrcLine(Duration(seconds: 10), 'b'),
      const LrcLine(Duration(seconds: 20), 'c'),
    ];
    test('pos 早于首行 => 0(clamp)', () {
      expect(currentIndexAt(lines, const Duration(seconds: -5)), 0);
    });
    test('pos 正好落在某行时间 => 该行', () {
      expect(currentIndexAt(lines, const Duration(seconds: 10)), 1);
    });
    test('pos 在两行之间 => 前一行', () {
      expect(currentIndexAt(lines, const Duration(seconds: 15)), 1);
    });
    test('pos 超过末行 => 末行', () {
      expect(currentIndexAt(lines, const Duration(seconds: 99)), 2);
    });
    test('空列表 => 0', () {
      expect(currentIndexAt(const <LrcLine>[], const Duration(seconds: 5)), 0);
    });
  });
}
