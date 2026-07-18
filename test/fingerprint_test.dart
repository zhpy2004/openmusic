import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/library/fingerprint.dart';

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('fp_test'));
  tearDown(() async => tmp.delete(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  test('相同内容不同文件名 → 指纹相同', () async {
    final a = write('a.mp3', List.generate(1000, (i) => i % 256));
    final b = write('b.mp3', List.generate(1000, (i) => i % 256));
    expect(await computeFileFingerprint(a), await computeFileFingerprint(b));
  });

  test('内容不同 → 指纹不同', () async {
    final a = write('a.mp3', List.generate(1000, (i) => i % 256));
    final b = write('b.mp3', List.generate(1000, (i) => (i + 1) % 256));
    expect(await computeFileFingerprint(a),
        isNot(await computeFileFingerprint(b)));
  });

  test('大于 256KB 的文件只取头尾——头尾同、长度同则指纹同（设计如此）', () async {
    final base = List.generate(300 * 1024, (i) => i % 256);
    final variant = List<int>.from(base)..[150 * 1024] = 99; // 只改中间一个字节
    final a = write('a.flac', base);
    final b = write('b.flac', variant);
    expect(await computeFileFingerprint(a), await computeFileFingerprint(b));
  });

  test('长度不同 → 指纹不同', () async {
    final a = write('a.mp3', List.filled(1000, 7));
    final b = write('b.mp3', List.filled(1001, 7));
    expect(await computeFileFingerprint(a),
        isNot(await computeFileFingerprint(b)));
  });

  test('空文件（0 字节）可算指纹，且与 1 字节文件不同', () async {
    final a = write('a.mp3', const []);
    final b = write('b.mp3', const [0]);
    final fpA = await computeFileFingerprint(a);
    expect(fpA, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(fpA, isNot(await computeFileFingerprint(b)));
  });

  test('正好 128KB：全文件都在头窗口内，改末字节 → 指纹变', () async {
    final base = List.generate(128 * 1024, (i) => i % 256);
    final variant = List<int>.from(base)..[128 * 1024 - 1] = 99;
    final a = write('a.mp3', base);
    final b = write('b.mp3', variant);
    expect(await computeFileFingerprint(a),
        isNot(await computeFileFingerprint(b)));
  });

  test('正好 256KB：头尾窗口拼接全覆盖，改 128KB 边界处字节 → 指纹变', () async {
    final base = List.generate(256 * 1024, (i) => i % 256);
    // 头窗口 [0,128K)，尾窗口 [128K,256K)：第 128K 字节是尾窗口首字节。
    final variant = List<int>.from(base)..[128 * 1024] = 99;
    final a = write('a.flac', base);
    final b = write('b.flac', variant);
    expect(await computeFileFingerprint(a),
        isNot(await computeFileFingerprint(b)));
  });

  test('128–256KB 之间（200KB）：头尾重叠全覆盖，改中间字节 → 指纹必须变', () async {
    // len=200K：头 [0,128K)，尾从 max(200K-128K,128K)=128K 起长 72K，
    // 即尾 [128K,200K)——无盲区，任何一个字节的改动都必须反映到指纹。
    final base = List.generate(200 * 1024, (i) => i % 256);
    final variant = List<int>.from(base)..[150 * 1024] = 99;
    final a = write('a.mp3', base);
    final b = write('b.mp3', variant);
    expect(await computeFileFingerprint(a),
        isNot(await computeFileFingerprint(b)));
  });

  test('golden：固定字节序列的指纹锁定为已知串（防格式漂移）', () async {
    final a = write('a.mp3', List.generate(1000, (i) => i % 256));
    // 值由当前实现（xxh3 无符号 16 位十六进制，"$len:"+头+尾）实测得出，
    // 一旦漂移说明指纹格式被破坏——M3 依赖它做跨设备持久身份，勿随意更新。
    expect(await computeFileFingerprint(a), '7e5c78c4f8abd284');
  });
}
