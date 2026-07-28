import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/request_auth.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  late SyncServer server;
  final key = List<int>.generate(32, (i) => i);

  setUp(() async {
    db = AppDatabase(testExecutor());
    await db.upsertPeer(
      deviceId: 'peer-1',
      deviceName: '手机',
      platform: 'android',
      sharedKey: base64.encode(key),
    );
    server = SyncServer(
      db: db,
      deviceId: 'server-1',
      deviceName: '台式机',
      platform: 'windows',
      trackCount: () async => 116,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await db.close();
  });

  Future<http.Response> getHello({Map<String, String>? headers}) => http.get(
    Uri.parse('http://127.0.0.1:${server.port}/v1/hello'),
    headers: headers,
  );

  test('start 后拿到一个真实端口', () {
    expect(server.port, greaterThan(0));
  });

  test('已配对设备签名后能拿到本机信息', () async {
    final headers = await signHeaders(
      deviceId: 'peer-1',
      sharedKey: key,
      method: 'GET',
      path: '/v1/hello',
      body: const [],
    );
    final res = await getHello(headers: headers);
    expect(res.statusCode, 200);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['did'], 'server-1');
    expect(body['name'], '台式机');
    expect(body['plat'], 'windows');
    expect(body['pv'], 1);
    expect(body['trackCount'], 116);
  });

  test('无签名 → 401 bad_signature', () async {
    final res = await getHello();
    expect(res.statusCode, 401);
    expect(jsonDecode(res.body)['reason'], 'bad_signature');
  });

  // deviceId 走 HTTP 头,必须是 ASCII(dart:io 会拒非 ASCII 头值);
  // 真实 deviceId 是 32 位十六进制,天然满足。设备名走 JSON 体,中文不受影响。
  test('未配对设备 → 401 unknown_device', () async {
    final headers = await signHeaders(
      deviceId: 'stranger-device',
      sharedKey: key,
      method: 'GET',
      path: '/v1/hello',
      body: const [],
    );
    final res = await getHello(headers: headers);
    expect(res.statusCode, 401);
    expect(jsonDecode(res.body)['reason'], 'unknown_device');
  });

  test('解除配对后原设备立刻被拒', () async {
    await db.deletePeer('peer-1');
    final headers = await signHeaders(
      deviceId: 'peer-1',
      sharedKey: key,
      method: 'GET',
      path: '/v1/hello',
      body: const [],
    );
    final res = await getHello(headers: headers);
    expect(res.statusCode, 401);
    expect(jsonDecode(res.body)['reason'], 'unknown_device');
  });

  test('时钟偏差过大 → 401 clock_skew', () async {
    final headers = await signHeaders(
      deviceId: 'peer-1',
      sharedKey: key,
      method: 'GET',
      path: '/v1/hello',
      body: const [],
      now: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    final res = await getHello(headers: headers);
    expect(res.statusCode, 401);
    expect(jsonDecode(res.body)['reason'], 'clock_skew');
  });

  test('重放同一签名 → 第二次 401 replay', () async {
    final headers = await signHeaders(
      deviceId: 'peer-1',
      sharedKey: key,
      method: 'GET',
      path: '/v1/hello',
      body: const [],
    );
    expect((await getHello(headers: headers)).statusCode, 200);
    final second = await getHello(headers: headers);
    expect(second.statusCode, 401);
    expect(jsonDecode(second.body)['reason'], 'replay');
  });

  test('未知路径 → 404', () async {
    final res = await http.get(
      Uri.parse('http://127.0.0.1:${server.port}/v1/nope'),
    );
    expect(res.statusCode, 404);
  });
}
