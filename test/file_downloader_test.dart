import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openmusic/src/library/fingerprint.dart';
import 'package:openmusic/src/sync/file_downloader.dart';

void main() {
  late Directory tmp;
  late HttpServer server;
  late File source;
  late String sourceFp;
  var failAfterBytes = -1; // >=0 时,发到这么多字节就掐断连接

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('om-dl');
    source = File('${tmp.path}/source.mp3');
    // 300KB:超过指纹的头尾各 128KB,能真正体现"中间字节"的差异
    await source.writeAsBytes(
      List<int>.generate(300 * 1024, (i) => (i * 7) % 256),
    );
    sourceFp = await computeFileFingerprint(source);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == '/gone') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final bytes = await source.readAsBytes();
      var start = 0;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.startsWith('bytes=')) {
        start = int.tryParse(range.substring(6).split('-').first) ?? 0;
      }
      final slice = bytes.sublist(start);
      req.response.statusCode = start > 0 ? 206 : 200;
      req.response.headers.contentLength = slice.length;
      if (failAfterBytes >= 0) {
        // 只发一部分然后掐断,模拟传输中断
        req.response.add(slice.sublist(0, failAfterBytes));
        await req.response.flush();
        await req.response.close().catchError((_) {});
        return;
      }
      req.response.add(slice);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String url(String path) => 'http://127.0.0.1:${server.port}$path';
  Future<Map<String, String>> noSign(String m, String path) async => {};

  FileDownloader downloader(Directory dir) =>
      FileDownloader(httpClient: http.Client(), dir: dir);

  test('完整下载成功:文件落盘、指纹与源一致、无 .part 残留', () async {
    final dest = await Directory('${tmp.path}/dest').create();
    failAfterBytes = -1;

    final r = await downloader(dest).download(
      url: url('/file'),
      fileName: '及时雨.mp3',
      expectedFp: sourceFp,
      sign: noSign,
    );

    expect(r.outcome, DownloadOutcome.saved);
    final saved = File(r.savedPath!);
    expect(await computeFileFingerprint(saved), sourceFp);
    expect(
      dest.listSync().where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('中途断开后重来:从断点续传,最终字节与源完全一致', () async {
    final dest = await Directory('${tmp.path}/dest2').create();

    failAfterBytes = 100 * 1024; // 第一次只发 100KB 就断
    final first = await downloader(dest).download(
      url: url('/file'),
      fileName: '及时雨.mp3',
      expectedFp: sourceFp,
      sign: noSign,
    );
    expect(first.outcome, DownloadOutcome.failed);
    // .part 必须留着,否则续传无从谈起
    final parts = dest.listSync().where((e) => e.path.endsWith('.part'));
    expect(parts.length, 1);

    failAfterBytes = -1; // 第二次正常发
    final second = await downloader(dest).download(
      url: url('/file'),
      fileName: '及时雨.mp3',
      expectedFp: sourceFp,
      sign: noSign,
    );
    expect(second.outcome, DownloadOutcome.saved);
    expect(
      await File(second.savedPath!).readAsBytes(),
      await source.readAsBytes(),
    );
  });

  test('指纹对不上:删掉 .part,不产出正式文件', () async {
    final dest = await Directory('${tmp.path}/dest3').create();
    failAfterBytes = -1;

    final r = await downloader(dest).download(
      url: url('/file'),
      fileName: '及时雨.mp3',
      expectedFp: 'ffffffffffffffff', // 故意给错
      sign: noSign,
    );

    expect(r.outcome, DownloadOutcome.checksumFailed);
    expect(dest.listSync(), isEmpty); // 既没有正式文件,也没有 .part 残留
  });

  test('同名文件已存在:加后缀,绝不覆盖', () async {
    final dest = await Directory('${tmp.path}/dest4').create();
    final existing = File('${dest.path}/及时雨.mp3');
    await existing.writeAsString('别人的文件');
    failAfterBytes = -1;

    final r = await downloader(dest).download(
      url: url('/file'),
      fileName: '及时雨.mp3',
      expectedFp: sourceFp,
      sign: noSign,
    );

    expect(r.outcome, DownloadOutcome.saved);
    expect(r.savedPath, endsWith('及时雨 (2).mp3'));
    expect(await existing.readAsString(), '别人的文件'); // 原文件没被动
  });

  test('(2) 也被占时递增到 (3)', () async {
    final dest = await Directory('${tmp.path}/dest5').create();
    await File('${dest.path}/及时雨.mp3').writeAsString('x');
    await File('${dest.path}/及时雨 (2).mp3').writeAsString('y');
    failAfterBytes = -1;

    final r = await downloader(dest).download(
      url: url('/file'),
      fileName: '及时雨.mp3',
      expectedFp: sourceFp,
      sign: noSign,
    );

    expect(r.savedPath, endsWith('及时雨 (3).mp3'));
  });

  test('对端没有该文件(404):记为 peerMissing,不算失败', () async {
    final dest = await Directory('${tmp.path}/dest6').create();
    final r = await downloader(dest).download(
      url: url('/gone'),
      fileName: '及时雨.mp3',
      expectedFp: sourceFp,
      sign: noSign,
    );
    expect(r.outcome, DownloadOutcome.peerMissing);
  });

  test('sidecar 下载:按字节数校验,对不上就丢弃', () async {
    final dest = await Directory('${tmp.path}/dest7').create();
    failAfterBytes = -1;
    final ok = await downloader(dest).downloadSidecar(
      url: url('/file'),
      destPath: '${dest.path}/cover.jpg',
      sign: noSign,
    );
    expect(ok, isTrue);
    expect(await File('${dest.path}/cover.jpg').length(), 300 * 1024);
  });
}
