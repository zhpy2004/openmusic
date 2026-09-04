import 'dart:io';

import 'gen_gapless_tracks.dart' show readPcmSamples, zeroCrossingRate;

/// 分析一段真机录制的 gapless 播放录音(WAV,16-bit PCM),寻找 440Hz→1760Hz
/// 的频率跳变点(即两首测试音轨的边界),报告边界附近是否存在:
/// - 静音间隙(gap):边界前后有一段采样点全接近 0
/// - 波形突变(疑似爆音):相邻采样点振幅跳变异常大
///
/// 用法:`dart run tool/check_gapless.dart <录音文件.wav>`
/// 录音文件需先用 tool/gen_gapless_tracks.dart 生成的两首连续播放并录制得到。
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/check_gapless.dart <录音文件.wav>');
    exit(64);
  }
  final samples = readPcmSamples(File(args[0]));
  const windowSize = 400; // 约 9ms @44.1kHz,足够判断局部频率特征

  // 1. 找静音区间(可能是录音本身的头尾静音,也可能是播放留下的 gap)
  final silentRanges = <(int, int)>[];
  var silentStart = -1;
  for (var i = 0; i < samples.length; i++) {
    final isSilent = samples[i].abs() < 200; // 录音底噪容忍阈值
    if (isSilent && silentStart < 0) {
      silentStart = i;
    } else if (!isSilent && silentStart >= 0) {
      final len = i - silentStart;
      if (len > (44100 * 0.05).round()) {
        silentRanges.add((silentStart, i)); // >50ms 才算
      }
      silentStart = -1;
    }
  }

  stdout.writeln('采样点总数: ${samples.length}');
  if (silentRanges.isEmpty) {
    stdout.writeln('未检测到超过 50ms 的静音区间(不含首尾)。');
  } else {
    stdout.writeln('检测到 ${silentRanges.length} 段可能的静音间隙:');
    for (final r in silentRanges) {
      final ms = ((r.$2 - r.$1) / 44100 * 1000).round();
      stdout.writeln('  采样点 ${r.$1}-${r.$2}(约 ${ms}ms)');
    }
    stdout.writeln('若其中一段落在录音中段(不是开头/结尾的录制前后静音),'
        '很可能就是两曲之间的 gap。');
  }

  // 2. 扫描过零率的突变点,粗略定位"疑似频率切换"的位置
  final zcrs = <double>[];
  for (var i = 0; i + windowSize < samples.length; i += windowSize) {
    zcrs.add(zeroCrossingRate(samples.sublist(i, i + windowSize)));
  }
  var maxJump = 0.0;
  var maxJumpAt = 0;
  for (var i = 1; i < zcrs.length; i++) {
    final jump = (zcrs[i] - zcrs[i - 1]).abs();
    if (jump > maxJump) {
      maxJump = jump;
      maxJumpAt = i;
    }
  }
  final approxSample = maxJumpAt * windowSize;
  stdout.writeln('过零率突变最大处约在采样点 $approxSample'
      '(约 ${(approxSample / 44100).toStringAsFixed(2)}s),推测是两曲边界。');
  stdout.writeln('人工复核:在这个时间点附近回放录音,听是否有可感知的静音/'
      '咔哒声/音量突变——脚本只给出候选位置,最终判断仍需要人耳确认。');
}
