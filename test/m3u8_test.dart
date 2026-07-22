import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/library/m3u8.dart';

void main() {
  test('序列化:相对路径 + EXTINF', () {
    final text = serializeM3u8(
      baseDir: r'C:\Music',
      entries: const [
        M3u8Entry(
          absPath: r'C:\Music\a.mp3',
          artist: 'Aria',
          title: 'A',
          durationSec: 15,
        ),
        M3u8Entry(
          absPath: r'C:\Music\sub\b.mp3',
          artist: '',
          title: 'B',
          durationSec: 0,
        ),
      ],
    );
    expect(text, contains('#EXTM3U'));
    expect(text, contains('#EXTINF:15,Aria - A'));
    expect(text, contains('#EXTINF:0,B')); // 无歌手时只写标题
    // 相对于 baseDir、正斜杠
    expect(text, contains('a.mp3'));
    expect(text, contains('sub/b.mp3'));
    expect(text, isNot(contains(r'C:\Music')));
  });

  test('解析:相对路径解析回绝对 + 忽略注释/空行', () {
    const text = '''
#EXTM3U
#EXTINF:15,Aria - A
a.mp3
#EXTINF:0,B
sub/b.mp3
# 注释行忽略

missing.mp3
''';
    final r = parseM3u8(text: text, baseDir: r'C:\Music');
    expect(r.paths, [
      'C:/Music/a.mp3',
      'C:/Music/sub/b.mp3',
      'C:/Music/missing.mp3',
    ]);
  });

  test('matchPaths:按曲库路径匹配,未命中计数', () {
    final res = matchPaths(
      paths: ['C:/Music/a.mp3', 'C:/Music/gone.mp3'],
      libraryPathToFp: {'C:/Music/a.mp3': 'fpA'},
    );
    expect(res.matchedFps, ['fpA']);
    expect(res.unmatched, 1);
  });

  test('matchPaths:默认大小写敏感,大小写不同则未匹配', () {
    final res = matchPaths(
      paths: ['c:/music/a.mp3'],
      libraryPathToFp: {'C:/Music/a.mp3': 'fpA'},
    );
    expect(res.matchedFps, isEmpty);
    expect(res.unmatched, 1);
  });

  test('matchPaths:caseInsensitive 折叠大小写(Windows 路径)', () {
    final res = matchPaths(
      paths: ['c:/music/a.mp3', 'C:/Music/GONE.mp3'],
      libraryPathToFp: {'C:/Music/a.mp3': 'fpA'},
      caseInsensitive: true,
    );
    expect(res.matchedFps, ['fpA']);
    expect(res.unmatched, 1);
  });

  test('序列化:标签内换行被压成空格,不注入多余行', () {
    final text = serializeM3u8(
      baseDir: r'C:\Music',
      entries: const [
        M3u8Entry(
          absPath: r'C:\Music\a.mp3',
          artist: 'A\nB',
          title: 'T\r\nU',
          durationSec: 1,
        ),
      ],
    );
    expect(text, contains('#EXTINF:1,A B - T U'));
    // 正文只有 3 行:#EXTM3U / #EXTINF / a.mp3(尾随换行不计)。
    expect(text.trim().split('\n').length, 3);
  });

  test('往返:序列化后再解析,路径还原成原绝对路径', () {
    const base = r'C:\Music';
    final text = serializeM3u8(
      baseDir: base,
      entries: const [
        M3u8Entry(
          absPath: r'C:\Music\sub\b.mp3',
          artist: 'X',
          title: 'B',
          durationSec: 3,
        ),
      ],
    );
    final parsed = parseM3u8(text: text, baseDir: base);
    expect(parsed.paths, ['C:/Music/sub/b.mp3']);
  });
}
