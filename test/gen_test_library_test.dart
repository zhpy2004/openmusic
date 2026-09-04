import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_test_library.dart' as gen;

void main() {
  test('generateTestLibrary 生成的文件可被 audio_metadata_reader 正确读回标题/歌手/专辑', () async {
    final dir = await Directory.systemTemp.createTemp('gen_test_library_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    await gen.generateTestLibrary(dir.path, 5);

    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, 5);

    final meta = readMetadata(files.first, getImage: false);
    expect(meta.title, isNotNull);
    expect(meta.artist, isNotNull);
    expect(meta.album, isNotNull);
    expect(meta.duration, isNotNull);
    expect(meta.duration!.inMilliseconds, greaterThan(0));
  });

  test('生成的标题/歌手在不同文件间可区分(用于测搜索命中)', () async {
    final dir = await Directory.systemTemp.createTemp('gen_test_library_test2');
    addTearDown(() => dir.deleteSync(recursive: true));

    await gen.generateTestLibrary(dir.path, 10);

    final titles = dir
        .listSync()
        .whereType<File>()
        .map((f) => readMetadata(f, getImage: false).title)
        .toSet();
    expect(titles.length, 10); // 10 个文件 10 个不同标题
  });
}
