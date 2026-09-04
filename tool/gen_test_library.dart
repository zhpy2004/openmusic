import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// 生成 [count] 个最小合法 WAV 静音文件到 [outDir],标题/歌手/专辑各不相同。
/// 只用于测扫描/列表/搜索的规模性能,不含真实可听内容——WAV 是刻意选择:
/// 复用应用自己读标签用的 audio_metadata_reader 的 RiffWriter 写回标签,
/// 保证与应用的读取路径天然兼容,不必手工拼别的格式的帧字节。
Future<void> generateTestLibrary(String outDir, int count) async {
  final dir = Directory(outDir)..createSync(recursive: true);
  for (var i = 0; i < count; i++) {
    final file = File('${dir.path}/track_$i.wav');
    file.writeAsBytesSync(_silentWavBytes(durationMs: 300));

    // 不用包顶层的 updateMetadata()/writeMetadata():writeMetadata()
    // (lib/src/writer.dart)为了嗅探容器格式会自己 openSync() 一个
    // RandomAccessFile,但嗅探完直接委托给 RiffWriter 就返回,从未
    // closeSync() 那个句柄——在 Windows 上会一直占着文件不放,后面
    // 想删测试目录就会报"另一个程序正在使用此文件"。这里已经确定是
    // 我们自己刚写的 WAV,直接读+改+用 RiffWriter 写回,跳过那次会
    // 漏关句柄的嗅探。
    final meta = readAllMetadata(file) as RiffMetadata;
    meta.setTitle('Test Track $i');
    meta.setArtist('Test Artist ${i % 200}');
    meta.setAlbum('Test Album ${i % 50}');
    RiffWriter().write(file, meta);
  }
}

/// 最小合法 WAV:RIFF/WAVE 头 + fmt 块 + 一个空的 LIST/INFO 块 + [durationMs]
/// 毫秒静音 PCM 数据块(16-bit mono 8kHz——采样率刻意选低,只为文件小、
/// 生成快,不追求音质)。
///
/// 关键点(踩坑记录):`package:audio_metadata_reader` 的 RiffWriter
/// (lib/src/writers/riff_writer.dart)只会**覆写已存在的 LIST/INFO 块**,
/// 遇不到 LIST/INFO 块时不会新插入一个——裸的 fmt+data WAV 骨架写标签会
/// 被静默丢弃(不报错,读回来 title 全是 null)。所以这里必须预先塞一个
/// 空的 LIST/INFO 占位块,后续 updateMetadata 才有东西可覆写。
Uint8List _silentWavBytes({required int durationMs}) {
  const sampleRate = 8000;
  const bitsPerSample = 16;
  const channels = 1;
  final sampleCount = (sampleRate * durationMs / 1000).round();
  final dataSize = sampleCount * channels * (bitsPerSample ~/ 8);
  const byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  const blockAlign = channels * (bitsPerSample ~/ 8);

  void ascii(BytesBuilder b, String s) => b.add(s.codeUnits);
  void u32(BytesBuilder b, int v) => b.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
  void u16(BytesBuilder b, int v) => b.add([v & 0xff, (v >> 8) & 0xff]);

  final fmtChunk = BytesBuilder();
  ascii(fmtChunk, 'fmt ');
  u32(fmtChunk, 16);
  u16(fmtChunk, 1); // PCM
  u16(fmtChunk, channels);
  u32(fmtChunk, sampleRate);
  u32(fmtChunk, byteRate);
  u16(fmtChunk, blockAlign);
  u16(fmtChunk, bitsPerSample);

  // 空 LIST/INFO 占位块:size=4 只算上 "INFO" 四个字节,不含任何子块。
  final listChunk = BytesBuilder();
  ascii(listChunk, 'LIST');
  u32(listChunk, 4);
  ascii(listChunk, 'INFO');

  final dataChunk = BytesBuilder();
  ascii(dataChunk, 'data');
  u32(dataChunk, dataSize);
  dataChunk.add(List.filled(dataSize, 0)); // 全 0 字节 = 静音

  final payload = BytesBuilder()
    ..add(fmtChunk.toBytes())
    ..add(listChunk.toBytes())
    ..add(dataChunk.toBytes());
  final payloadBytes = payload.toBytes();

  final wav = BytesBuilder();
  ascii(wav, 'RIFF');
  u32(wav, 4 + payloadBytes.length); // "WAVE" + 所有子块
  ascii(wav, 'WAVE');
  wav.add(payloadBytes);

  return wav.toBytes();
}

/// 命令行入口:`dart run tool/gen_test_library.dart <输出目录> <数量>`
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('用法: dart run tool/gen_test_library.dart <输出目录> <数量>');
    exit(64);
  }
  final outDir = args[0];
  final count = int.parse(args[1]);
  final sw = Stopwatch()..start();
  await generateTestLibrary(outDir, count);
  stdout.writeln('已生成 $count 个测试文件到 $outDir,耗时 ${sw.elapsedMilliseconds}ms');
}
