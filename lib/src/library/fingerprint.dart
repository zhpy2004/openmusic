import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:xxh3/xxh3.dart';

const _chunk = 128 * 1024;

/// 内容指纹 = xxh3(文件长度 + 头 128KB + 尾 128KB)，见 spec §5 数据模型要点。
/// 格式：16 位小写无符号十六进制（定长，不足左补 0），可跨设备做持久身份。
/// 改文件名/挪目录不变；只改中间字节（超出头尾范围）不变，属设计取舍。
Future<String> computeFileFingerprint(File file) async {
  final raf = await file.open();
  try {
    final len = await raf.length();
    final headLen = min(_chunk, len);
    await raf.setPosition(0);
    final head = await _readFully(raf, headLen);
    Uint8List tail = Uint8List(0);
    if (len > _chunk) {
      await raf.setPosition(max(len - _chunk, headLen));
      tail = await _readFully(raf, min(_chunk, len - headLen));
    }
    final buf = BytesBuilder(copy: false)
      ..add(utf8.encode('$len:'))
      ..add(head)
      ..add(tail);
    return xxh3String(buf.toBytes()).padLeft(16, '0');
  } finally {
    await raf.close();
  }
}

/// 循环读满 [count] 字节（或至 EOF 提前结束）。
/// RandomAccessFile.read 允许短读（网络盘上尤其可能），单次调用不可靠。
Future<Uint8List> _readFully(RandomAccessFile raf, int count) async {
  final out = Uint8List(count);
  var offset = 0;
  while (offset < count) {
    final chunk = await raf.read(count - offset);
    if (chunk.isEmpty) break; // EOF
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return offset == count ? out : Uint8List.sublistView(out, 0, offset);
}
