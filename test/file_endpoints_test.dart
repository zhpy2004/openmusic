import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/request_auth.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  late SyncServer server;
  late Directory tmp;
  final key = List<int>.generate(32, (i) => i);
  final audio = List<int>.generate(5000, (i) => i % 256);

  setUp(() async {
    db = AppDatabase(testExecutor());
    tmp = await Directory.systemTemp.createTemp('om-files');
    await db.upsertPeer(
      deviceId: 'peer-1',
      deviceName: '手机',
      platform: 'android',
      sharedKey: base64.encode(key),
    );

    // 有文件的曲目
    final present = File('${tmp.path}/及时雨.mp3');
    await present.writeAsBytes(audio);
    await File('${tmp.path}/及时雨.jpg').writeAsBytes([1, 2, 3]);
    await db.upsertTrack(
      TracksCompanion.insert(
        path: present.path,
        fingerprint: 'fp-present',
        title: '及时雨',
        sizeBytes: audio.length,
        mtimeMs: 1,
      ),
    );
    // 库里有行、磁盘上没文件的曲目(扫描后被用户删了)
    await db.upsertTrack(
      TracksCompanion.insert(
        path: '${tmp.path}/已删除.mp3',
        fingerprint: 'fp-gone',
        title: '已删除',
        sizeBytes: 1,
        mtimeMs: 1,
      ),
    );

    server = SyncServer(
      db: db,
      deviceId: 'server-1',
      deviceName: '台式机',
      platform: 'windows',
      trackCount: () async => 2,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<http.Response> signedGet(String path, {String? range}) async {
    final headers = await signHeaders(
      deviceId: 'peer-1',
      sharedKey: key,
      method: 'GET',
      path: path,
      body: const [],
    );
    return http.get(
      Uri.parse('http://127.0.0.1:${server.port}$path'),
      headers: {...headers, if (range != null) 'range': range},
    );
  }

  test('清单只列磁盘上真实存在文件的曲目', () async {
    final res = await signedGet('/v1/files/manifest');
    expect(res.statusCode, 200);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    expect(list.length, 1); // fp-gone 不在里面
    final entry = list.single as Map<String, dynamic>;
    expect(entry['fp'], 'fp-present');
    expect(entry['name'], '及时雨.mp3');
    expect(entry['size'], audio.length);
    expect(entry['hasCover'], isTrue);
    expect(entry['hasLyrics'], isFalse);
  });

  test('下载完整文件:字节与磁盘一致', () async {
    final res = await signedGet('/v1/file/fp-present');
    expect(res.statusCode, 200);
    expect(res.bodyBytes, audio);
    expect(res.headers['accept-ranges'], 'bytes');
  });

  test('Range 请求返回 206 且字节正确', () async {
    final res = await signedGet('/v1/file/fp-present', range: 'bytes=1000-');
    expect(res.statusCode, 206);
    expect(res.bodyBytes, audio.sublist(1000));
  });

  test('磁盘上没有文件的指纹 → 404', () async {
    final res = await signedGet('/v1/file/fp-gone');
    expect(res.statusCode, 404);
  });

  test('封面能取到,歌词没有则 404(正常情况)', () async {
    final cover = await signedGet('/v1/sidecar/fp-present/cover');
    expect(cover.statusCode, 200);
    expect(cover.bodyBytes, [1, 2, 3]);

    final lyrics = await signedGet('/v1/sidecar/fp-present/lyrics');
    expect(lyrics.statusCode, 404);
  });

  test('未签名的文件请求被 401 挡住', () async {
    final res = await http.get(
      Uri.parse('http://127.0.0.1:${server.port}/v1/file/fp-present'),
    );
    expect(res.statusCode, 401);
  });
}
