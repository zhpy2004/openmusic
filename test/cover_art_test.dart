import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/library/cover_art.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('om_cover'));
  tearDown(() async => dir.delete(recursive: true));

  test('存在同名 .jpg 时返回该路径', () async {
    final audio = '${dir.path}/song.mp3';
    await File(audio).writeAsBytes(const [1]);
    await File('${dir.path}/song.jpg').writeAsBytes(const [2]);
    expect(await resolveCoverPath(audio), '${dir.path}/song.jpg');
  });

  test('无 .jpg 但有 .png 时返回 .png', () async {
    final audio = '${dir.path}/song.mp3';
    await File(audio).writeAsBytes(const [1]);
    await File('${dir.path}/song.png').writeAsBytes(const [2]);
    expect(await resolveCoverPath(audio), '${dir.path}/song.png');
  });

  test('都没有时返回 null', () async {
    final audio = '${dir.path}/song.mp3';
    await File(audio).writeAsBytes(const [1]);
    expect(await resolveCoverPath(audio), isNull);
  });
}
