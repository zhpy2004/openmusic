import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/app/providers.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('om_lrc'));
  tearDown(() async => dir.delete(recursive: true));

  test('存在同名 .lrc 且含时间轴 => 解析为 synced', () async {
    final audio = '${dir.path}/song.mp3';
    await File(audio).writeAsBytes(const [1]);
    await File('${dir.path}/song.lrc').writeAsString('[00:01.00]hi');
    final r = await resolveLyrics(audio);
    expect(r, isNotNull);
    expect(r!.synced, true);
    expect(r.lines.single.text, 'hi');
  });

  test('纯文本 .lrc => synced=false', () async {
    final audio = '${dir.path}/song.mp3';
    await File(audio).writeAsBytes(const [1]);
    await File('${dir.path}/song.lrc').writeAsString('第一行\n第二行');
    final r = await resolveLyrics(audio);
    expect(r!.synced, false);
    expect(r.lines.length, 2);
  });

  test('无 .lrc => null', () async {
    final audio = '${dir.path}/song.mp3';
    await File(audio).writeAsBytes(const [1]);
    expect(await resolveLyrics(audio), isNull);
  });

  test('空 .lrc => null(无有效行)', () async {
    final audio = '${dir.path}/song.mp3';
    await File(audio).writeAsBytes(const [1]);
    await File('${dir.path}/song.lrc').writeAsString('   \n  ');
    expect(await resolveLyrics(audio), isNull);
  });
}
