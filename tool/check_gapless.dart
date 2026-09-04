import 'dart:io';
import 'dart:math' as math;

import 'gen_gapless_tracks.dart' show zeroCrossingRate;

/// 分析一段真机录制的 gapless 播放录音(WAV,16-bit PCM),寻找 440Hz→1760Hz
/// (见 gen_gapless_tracks.dart)的频率跳变点(即两首测试音轨的边界),报告:
/// - 静音间隙(gap):边界前后有一段采样点全接近 0
/// - 边界位置估计:基于过零率(ZCR)突变定位,已排除录音头尾静音区间的干扰
/// - 振幅突变(疑似爆音/咔哒声):相邻采样点跳变远超正弦波正常斜率的位置
///
/// 是否真的存在可感知的爆音/静音跳变,脚本只给出候选位置,最终判断仍需
/// 要人耳复核——这里的检测都是粗略启发式,不是精确的音频分析。
///
/// 用法:`dart run tool/check_gapless.dart <录音文件.wav>`
/// 录音文件需先用 tool/gen_gapless_tracks.dart 生成的两首连续播放并录制得到。
///
/// WAV 解析:真实录音的采样率、声道数、chunk 排布都不像生成器自己产出的文件
/// 那样可控(常见 48kHz、双声道、`fmt `/`data` 之前还夹着 `LIST`/`fact` 等
/// chunk),所以这里按 chunk ID 扫描定位 `fmt ` 与 `data`,不假设固定的 44
/// 字节头偏移。多声道时按帧平均下混为单声道——过零率等分析都基于单一采样
/// 序列,交织的多声道数据会让过零率在声道间来回跳变,失去意义。
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/check_gapless.dart <录音文件.wav>');
    exit(64);
  }

  final wav = _readWavPcm(File(args[0]));
  final samples = wav.samples;
  final sampleRate = wav.sampleRate;
  stdout.writeln(
      '检测到 WAV 参数: 采样率 ${sampleRate}Hz, 声道数 ${wav.channels}'
      '${wav.channels > 1 ? '(已下混为单声道用于分析)' : ''}, 采样点总数 ${samples.length}');

  final windowSize = math.max(1, (sampleRate * 0.009).round()); // 约 9ms,足够判断局部频率特征
  final silentGapSamples = (sampleRate * 0.05).round(); // >50ms 才算静音间隙

  // 1. 找静音区间(可能是录音本身的头尾静音,也可能是播放留下的 gap)
  final silentRanges = <(int, int)>[];
  var silentStart = -1;
  for (var i = 0; i < samples.length; i++) {
    final isSilent = samples[i].abs() < 200; // 录音底噪容忍阈值
    if (isSilent && silentStart < 0) {
      silentStart = i;
    } else if (!isSilent && silentStart >= 0) {
      final len = i - silentStart;
      if (len > silentGapSamples) {
        silentRanges.add((silentStart, i));
      }
      silentStart = -1;
    }
  }
  // 文件在静音中结束时,循环里的 else 分支永远不会触发(没有下一个非静音
  // 采样点把它推进 silentRanges),这里补上收尾的那一段,否则录音结尾的
  // 静音(很可能正是我们要找的尾部 gap)会被悄悄漏报。
  if (silentStart >= 0) {
    final len = samples.length - silentStart;
    if (len > silentGapSamples) {
      silentRanges.add((silentStart, samples.length));
    }
  }

  if (silentRanges.isEmpty) {
    stdout.writeln('未检测到超过 50ms 的静音区间(不含首尾)。');
  } else {
    stdout.writeln('检测到 ${silentRanges.length} 段可能的静音间隙:');
    for (final r in silentRanges) {
      final ms = ((r.$2 - r.$1) / sampleRate * 1000).round();
      stdout.writeln('  采样点 ${r.$1}-${r.$2}(约 ${ms}ms)');
    }
    stdout.writeln('若其中一段落在录音中段(不是开头/结尾的录制前后静音),'
        '很可能就是两曲之间的 gap。');
  }

  // 2. 扫描过零率的突变点,粗略定位"疑似频率切换"的位置。
  //    排除与静音区间重叠的窗口——静音窗口的过零率≈0,录音头尾的静音
  //    (录制前/录制后按下按钮留下的空白)常常会产生比真正的两曲边界更大
  //    的过零率跳变,不排除的话很容易把"有声→头尾静音"误判成"两曲边界"。
  final zcrs = <double>[];
  for (var i = 0; i + windowSize < samples.length; i += windowSize) {
    zcrs.add(zeroCrossingRate(samples.sublist(i, i + windowSize)));
  }
  bool windowOverlapsSilence(int windowIndex) {
    final start = windowIndex * windowSize;
    final end = start + windowSize;
    for (final r in silentRanges) {
      if (start < r.$2 && end > r.$1) return true;
    }
    return false;
  }

  var maxJump = 0.0;
  var maxJumpAt = -1;
  for (var i = 1; i < zcrs.length; i++) {
    if (windowOverlapsSilence(i - 1) || windowOverlapsSilence(i)) continue;
    final jump = (zcrs[i] - zcrs[i - 1]).abs();
    if (jump > maxJump) {
      maxJump = jump;
      maxJumpAt = i;
    }
  }
  if (maxJumpAt < 0) {
    stdout.writeln('过零率分析:除静音区间外没有可比较的窗口,无法估计边界位置。');
  } else {
    final approxSample = maxJumpAt * windowSize;
    stdout.writeln('过零率突变最大处约在采样点 $approxSample'
        '(约 ${(approxSample / sampleRate).toStringAsFixed(2)}s),推测是两曲边界。');
  }

  // 3. 扫描相邻采样点的振幅跳变,粗略标记疑似"爆音/咔哒声"的位置。正弦波
  //    正常情况下相邻采样点变化是连续、光滑的;真正的爆音/咔哒声表现为
  //    个别采样点出现远超正常波形斜率的跳变。用整段录音跳变量的均值+标准
  //    差动态定阈值,而不是写死一个固定数,这样不同录音设备/电平下都能用。
  final clickRanges = _findAmplitudeJumps(samples);
  if (clickRanges.isEmpty) {
    stdout.writeln('未检测到明显的振幅突变(疑似爆音/咔哒声)。');
  } else {
    stdout.writeln('检测到 ${clickRanges.length} 处疑似爆音/咔哒声(振幅相邻跳变异常大):');
    for (final r in clickRanges.take(20)) {
      stdout.writeln('  采样点 ${r.$1}-${r.$2}'
          '(约 ${(r.$1 / sampleRate).toStringAsFixed(2)}s)');
    }
    if (clickRanges.length > 20) {
      stdout.writeln('  ...还有 ${clickRanges.length - 20} 处未列出');
    }
  }

  stdout.writeln('人工复核:在上述候选位置附近回放录音,听是否有可感知的静音/'
      '咔哒声/音量突变——脚本只给出候选位置,最终判断仍需要人耳确认。');
}

class _WavPcm {
  _WavPcm(this.samples, this.sampleRate, this.channels);

  /// 单声道采样点(多声道输入已下混)。
  final List<int> samples;
  final int sampleRate;
  final int channels;
}

/// 解析 WAV 文件:按 chunk ID 扫描找到 `fmt ` 与 `data`,不假设固定的 44
/// 字节头偏移(真实录音常见在两者之间夹带 `LIST`/`fact` 等 chunk)。只支持
/// 16-bit PCM(`gen_gapless_tracks.dart` 生成的测试音轨与常见录音软件默认
/// 输出都是这个格式);多声道按帧平均下混为单声道。
_WavPcm _readWavPcm(File f) {
  final bytes = f.readAsBytesSync();
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    stderr.writeln('错误: ${f.path} 不是有效的 WAV 文件(缺少 RIFF/WAVE 头)。');
    exit(65);
  }

  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  int? dataOffset;
  int? dataSize;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    final chunkDataStart = offset + 8;

    if (chunkId == 'fmt ' && chunkDataStart + 16 <= bytes.length) {
      channels = bytes[chunkDataStart + 2] | (bytes[chunkDataStart + 3] << 8);
      sampleRate = bytes[chunkDataStart + 4] |
          (bytes[chunkDataStart + 5] << 8) |
          (bytes[chunkDataStart + 6] << 16) |
          (bytes[chunkDataStart + 7] << 24);
      bitsPerSample =
          bytes[chunkDataStart + 14] | (bytes[chunkDataStart + 15] << 8);
    } else if (chunkId == 'data') {
      dataOffset = chunkDataStart;
      dataSize = chunkSize;
    }

    // RIFF chunk 按偶数字节对齐,奇数长度的 chunk 后面有 1 字节 padding。
    offset = chunkDataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (sampleRate == null || channels == null || bitsPerSample == null) {
    stderr.writeln('错误: ${f.path} 里没找到 fmt chunk,无法解析采样率/声道数。');
    exit(65);
  }
  if (dataOffset == null || dataSize == null) {
    stderr.writeln('错误: ${f.path} 里没找到 data chunk。');
    exit(65);
  }
  if (bitsPerSample != 16) {
    stderr.writeln('错误: 只支持 16-bit PCM,${f.path} 是 $bitsPerSample-bit。');
    exit(65);
  }
  if (channels < 1) {
    stderr.writeln('错误: ${f.path} 声道数异常($channels)。');
    exit(65);
  }

  final end = math.min(dataOffset + dataSize, bytes.length);
  final rawSamples = <int>[];
  for (var i = dataOffset; i + 1 < end; i += 2) {
    var v = bytes[i] | (bytes[i + 1] << 8);
    if (v >= 0x8000) v -= 0x10000;
    rawSamples.add(v);
  }

  List<int> mono;
  if (channels == 1) {
    mono = rawSamples;
  } else {
    // 多声道:按帧平均下混为单声道。简单、稳定,足够支撑静音/过零率/振幅
    // 突变这几种粗略分析,不需要为了这个离线校验工具引入完整的多声道处理。
    mono = <int>[];
    for (var i = 0; i + channels <= rawSamples.length; i += channels) {
      var sum = 0;
      for (var c = 0; c < channels; c++) {
        sum += rawSamples[i + c];
      }
      mono.add((sum / channels).round());
    }
  }

  return _WavPcm(mono, sampleRate, channels);
}

/// 找出相邻采样点振幅跳变远超正常水平的位置(疑似爆音/咔哒声),按位置相
/// 邻(10 个采样点内)合并成区间返回。
List<(int, int)> _findAmplitudeJumps(List<int> samples) {
  if (samples.length < 2) return [];

  final deltas = List<int>.generate(
      samples.length - 1, (i) => (samples[i + 1] - samples[i]).abs());

  final mean = deltas.reduce((a, b) => a + b) / deltas.length;
  final variance = deltas
          .map((d) => (d - mean) * (d - mean))
          .reduce((a, b) => a + b) /
      deltas.length;
  final stddev = math.sqrt(variance);
  // 均值 + 6 倍标准差:动态阈值,适应不同录音的电平/底噪;同时设一个绝对
  // 下限,避免在近乎全静音的录音里因为标准差极小而对底噪过度敏感。
  final threshold = math.max(mean + 6 * stddev, 3000.0);

  final ranges = <(int, int)>[];
  for (var i = 0; i < deltas.length; i++) {
    if (deltas[i] <= threshold) continue;
    final pos = i + 1; // delta[i] 是 samples[i] 到 samples[i+1] 的跳变
    if (ranges.isNotEmpty && pos - ranges.last.$2 <= 10) {
      ranges[ranges.length - 1] = (ranges.last.$1, pos);
    } else {
      ranges.add((pos, pos));
    }
  }
  return ranges;
}
