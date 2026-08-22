import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../library/fingerprint.dart';

/// 一次下载的结局。
enum DownloadOutcome {
  /// 落盘成功且指纹校验通过。
  saved,

  /// 对端没有这个文件(404)。**不算失败** —— 双方都缺而已。
  peerMissing,

  /// 下载完了但重算指纹对不上:`.part` 已删除,没有产出文件。
  checksumFailed,

  /// 网络中断/IO 错误等。`.part` 保留供下次续传。
  failed,
}

class DownloadResult {
  const DownloadResult(this.outcome, {this.savedPath, this.error});
  final DownloadOutcome outcome;

  /// 仅 [DownloadOutcome.saved] 时非空。
  final String? savedPath;
  final String? error;
}

/// 请求签名器:给定方法与路径,返回该请求要带的签名头。
/// 下载器不关心签名细节(那是 M3-A 的事),只负责把头带上。
typedef RequestSigner =
    Future<Map<String, String>> Function(String method, String path);

/// 单文件下载:Range 续传 → `.part` 临时文件 → **落盘前重算指纹** → 改名避让。
class FileDownloader {
  FileDownloader({required http.Client httpClient, required this.dir})
    : _http = httpClient;

  final http.Client _http;

  /// 落盘目录(同步下载目录)。
  final Directory dir;

  void close() => _http.close();

  /// 下载一个音频文件。
  ///
  /// [expectedFp] 是对端声称的内容指纹;**落盘前必须重算并核对**,
  /// 对不上就删掉 `.part`、不产出正式文件 —— 坏文件绝不能进曲库。
  Future<DownloadResult> download({
    required String url,
    required String fileName,
    required String expectedFp,
    required RequestSigner sign,
    void Function(int received, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final part = File(p.join(dir.path, '$fileName.part'));
    var resumeFrom = 0;
    if (await part.exists()) resumeFrom = await part.length();

    final uri = Uri.parse(url);
    try {
      final headers = await sign('GET', uri.path);
      final req = http.Request('GET', uri)
        ..headers.addAll({
          ...headers,
          if (resumeFrom > 0) 'range': 'bytes=$resumeFrom-',
        });
      final res = await _http.send(req);

      if (res.statusCode == 404) {
        return const DownloadResult(DownloadOutcome.peerMissing);
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        return DownloadResult(
          DownloadOutcome.failed,
          error: '对端返回 ${res.statusCode}',
        );
      }
      // 服务端忽略了 Range(返回 200)就得从头写,否则会把整份接在半截后面。
      final append = res.statusCode == 206 && resumeFrom > 0;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      var received = append ? resumeFrom : 0;
      final total = (res.contentLength ?? 0) + (append ? resumeFrom : 0);
      try {
        await for (final chunk in res.stream) {
          if (shouldCancel?.call() ?? false) {
            await sink.flush();
            await sink.close();
            // 取消不删 .part —— 下次接着传。
            return const DownloadResult(DownloadOutcome.failed, error: '已取消');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // —— 安全阀:落盘前重算指纹 ——
      final actualFp = await computeFileFingerprint(part);
      if (actualFp != expectedFp) {
        await part.delete();
        return const DownloadResult(DownloadOutcome.checksumFailed);
      }

      final dest = await _freeName(fileName);
      await part.rename(dest.path);
      return DownloadResult(DownloadOutcome.saved, savedPath: dest.path);
    } catch (e) {
      // .part 保留供续传(母 spec §8:断点续传)。
      return DownloadResult(DownloadOutcome.failed, error: '$e');
    }
  }

  /// 下载 sidecar(封面/歌词)。它们**没有指纹可校验**(不是音频),
  /// 按 Content-Length 核对字节数,缺斤少两就丢弃。
  Future<bool> downloadSidecar({
    required String url,
    required String destPath,
    required RequestSigner sign,
  }) async {
    final uri = Uri.parse(url);
    try {
      final headers = await sign('GET', uri.path);
      final res = await _http.get(uri, headers: headers);
      if (res.statusCode != 200) return false;
      final expected = res.contentLength;
      if (expected != null && res.bodyBytes.length != expected) return false;
      await File(destPath).writeAsBytes(res.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 找一个没被占用的文件名:`名字.mp3` → `名字 (2).mp3` → `名字 (3).mp3`…
  ///
  /// **绝不覆盖已有文件**(母 spec §7.5:宁可留重复,不可丢歌)。
  /// 反复同步、或从多台设备取同名文件时,`(2)` 也会被占,所以要递增。
  Future<File> _freeName(String fileName) async {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var candidate = File(p.join(dir.path, fileName));
    var n = 2;
    while (await candidate.exists()) {
      candidate = File(p.join(dir.path, '$base ($n)$ext'));
      n++;
    }
    return candidate;
  }
}
