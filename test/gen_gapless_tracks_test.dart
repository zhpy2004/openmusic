import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_gapless_tracks.dart' as gen;

void main() {
  test('生成的两首测试音轨:track1 末尾与 track2 开头都不是静音(便于录音后定位边界)', () async {
    final dir = await Directory.systemTemp.createTemp('gapless_gen_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final files = await gen.generateGaplessPair(dir.path);
    expect(files.length, 2);

    for (final f in files) {
      final samples = gen.readPcmSamples(File(f));
      // 首尾各取 100 个采样点,若全 0(静音)说明生成参数有问题——
      // gapless 边界要靠"有信号"才能在录音里辨认断点,不能掐头去尾都是静音。
      final head = samples.take(100);
      final tail = samples.skip(samples.length - 100);
      expect(head.any((s) => s != 0), isTrue, reason: '$f 开头不该是静音');
      expect(tail.any((s) => s != 0), isTrue, reason: '$f 结尾不该是静音');
    }
  });

  test('track1 结尾频率与 track2 开头频率不同,录音分析脚本靠这个频率跳变定位边界', () async {
    final dir = await Directory.systemTemp.createTemp('gapless_gen_test2');
    addTearDown(() => dir.deleteSync(recursive: true));

    final files = await gen.generateGaplessPair(dir.path);
    final s1 = gen.readPcmSamples(File(files[0]));
    final s2 = gen.readPcmSamples(File(files[1]));

    // 粗略过零率(zero-crossing rate)可以区分不同频率的正弦波,不需要做 FFT。
    final zcr1 = gen.zeroCrossingRate(s1.skip(s1.length - 400).toList());
    final zcr2 = gen.zeroCrossingRate(s2.take(400).toList());
    expect(
      (zcr1 - zcr2).abs(),
      greaterThan(0.04),
      reason: '两首末尾/开头的频率应明显不同,否则录音分析脚本定位不到边界',
    );
  });
}
