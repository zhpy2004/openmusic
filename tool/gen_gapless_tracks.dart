import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;

/// 生成一对边界可判定的测试音轨:track1(440Hz 正弦波,2 秒)+
/// track2(1760Hz 正弦波,2 秒,高两个八度)。两者首尾都不是静音、频率明显
/// 不同,便于录制播放输出后用 zeroCrossingRate 定位边界、判断有没有明显
/// 静音间隙或波形突变(爆音)。
///
/// 频率选择踩坑记录:原计划用 880Hz(整一个八度)。实测发现 440Hz 与 880Hz
/// 在测试用的 400 采样点窗口内,过零率理论差值约 0.01995,本就低于测试
/// 要求的 >0.02;窗口离散化后最好情况也只能刚好摸到 0.02 这个边界值,
/// 又被 double 浮点误差顶到 0.019999999999999997,导致测试稳定失败而非
/// 偶发抖动。改用 1760Hz(高两个八度,音高跳变依然清晰易辨)后,理论过
/// 零率差值约 0.06,有 3 倍于阈值的余量,不再卡在浮点边界上。
Future<List<String>> generateGaplessPair(String outDir) async {
  final dir = Directory(outDir)..createSync(recursive: true);
  final track1 = '${dir.path}/gapless_1_440hz.wav';
  final track2 = '${dir.path}/gapless_2_1760hz.wav';
  File(track1).writeAsBytesSync(_sineWav(freqHz: 440, durationMs: 2000));
  File(track2).writeAsBytesSync(_sineWav(freqHz: 1760, durationMs: 2000));
  return [track1, track2];
}

Uint8List _sineWav({required double freqHz, required int durationMs}) {
  const bitsPerSample = 16;
  const channels = 1;
  final sampleCount = (_sampleRate * durationMs / 1000).round();
  final dataSize = sampleCount * channels * (bitsPerSample ~/ 8);
  const byteRate = _sampleRate * channels * (bitsPerSample ~/ 8);
  const blockAlign = channels * (bitsPerSample ~/ 8);

  final buf = BytesBuilder();
  void ascii(String s) => buf.add(s.codeUnits);
  void u32(int v) => buf.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
  void u16(int v) => buf.add([v & 0xff, (v >> 8) & 0xff]);

  ascii('RIFF');
  u32(36 + dataSize);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(channels);
  u32(_sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  ascii('data');
  u32(dataSize);

  const amplitude = 0.6 * 32767; // 留点余量,避免削波
  for (var i = 0; i < sampleCount; i++) {
    final t = i / _sampleRate;
    final v = (amplitude * math.sin(2 * math.pi * freqHz * t)).round();
    buf.add([v & 0xff, (v >> 8) & 0xff]); // little-endian int16
  }
  return buf.toBytes();
}

/// 读出 WAV 文件的 16-bit PCM 采样点(跳过 44 字节标准头)。
/// 只服务本工具与其测试,不追求通用 WAV 解析健壮性。
List<int> readPcmSamples(File f) {
  final bytes = f.readAsBytesSync();
  final data = bytes.sublist(44); // 标准 44 字节头之后就是 data
  final samples = <int>[];
  for (var i = 0; i + 1 < data.length; i += 2) {
    var v = data[i] | (data[i + 1] << 8);
    if (v >= 0x8000) v -= 0x10000; // 转有符号
    samples.add(v);
  }
  return samples;
}

/// 过零率:每个采样点符号变化的比例,粗略反映频率高低,足够区分本工具
/// 生成的 440Hz/1760Hz 两种测试音,不需要引入 FFT 依赖。
double zeroCrossingRate(List<int> samples) {
  if (samples.length < 2) return 0;
  var crossings = 0;
  for (var i = 1; i < samples.length; i++) {
    if ((samples[i - 1] >= 0) != (samples[i] >= 0)) crossings++;
  }
  return crossings / samples.length;
}

/// 命令行入口:`dart run tool/gen_gapless_tracks.dart <输出目录>`
Future<void> main(List<String> args) async {
  final outDir = args.isNotEmpty ? args[0] : '.';
  final files = await generateGaplessPair(outDir);
  stdout.writeln('已生成 gapless 测试音轨:\n${files.join('\n')}');
  stdout.writeln('把这两首加入播放队列连续播放并录音,再用 '
      'tool/check_gapless.dart 分析录音文件。');
}
