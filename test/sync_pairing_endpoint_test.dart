import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/pair_crypto.dart';
import 'package:openmusic/src/sync/request_auth.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  late SyncServer server;
  final requests = <PairRequest>[];

  setUp(() async {
    requests.clear();
    db = AppDatabase(testExecutor());
    server = SyncServer(
      db: db,
      deviceId: 'server-1',
      deviceName: '台式机',
      platform: 'windows',
      trackCount: () async => 0,
      onPairRequest: requests.add,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await db.close();
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  Future<http.Response> postHello({
    String did = 'client-1',
    String name = '手机',
    String? pubkey,
  }) => http.post(
    url('/v1/pair/hello'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'did': did,
      'name': name,
      'plat': 'android',
      'pubkey': pubkey ?? base64.encode(List<int>.filled(32, 1)),
    }),
  );

  /// 扮演发起方:生成密钥对、打 /v1/pair/hello、算出共享密钥与配对码。
  Future<({List<int> key, String code})> doHello({
    String did = 'client-1',
  }) async {
    final keys = await generatePairKeys();
    final res = await postHello(
      did: did,
      pubkey: base64.encode(keys.publicKeyBytes),
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final key = await deriveSharedKey(
      myKeyPair: keys.keyPair,
      theirPublicKey: base64.decode(body['pubkey'] as String),
      myDeviceId: did,
      theirDeviceId: body['did'] as String,
    );
    return (key: key, code: await pairingCode(key, did, body['did'] as String));
  }

  Future<http.Response> doConfirm(
    List<int> key, {
    String did = 'client-1',
  }) async {
    final body = utf8.encode(jsonEncode({'did': did}));
    final headers = await signHeaders(
      deviceId: did,
      sharedKey: key,
      method: 'POST',
      path: '/v1/pair/confirm',
      body: body,
    );
    return http.post(
      url('/v1/pair/confirm'),
      headers: {...headers, 'content-type': 'application/json'},
      body: body,
    );
  }

  test('hello 触发 UI 回调,两端算出同一个 6 位码', () async {
    final client = await doHello();
    expect(requests.length, 1);
    expect(requests.single.deviceName, '手机');
    expect(requests.single.code, client.code);
    expect(client.code.length, 6);
  });

  test('用户还没确认时 confirm 返回 409', () async {
    final client = await doHello();
    final res = await doConfirm(client.key);
    expect(res.statusCode, 409);
    expect(jsonDecode(res.body)['reason'], 'pending');
    expect(await db.getPeer('client-1'), isNull);
  });

  test('用户确认后 confirm 返回 200 并落库', () async {
    final client = await doHello();
    server.acceptPendingPair();
    final res = await doConfirm(client.key);
    expect(res.statusCode, 200);
    final peer = await db.getPeer('client-1');
    expect(peer!.deviceName, '手机');
    expect(peer.platform, 'android');
    expect(base64.decode(peer.sharedKey), client.key);
  });

  test('落库后普通签名请求即可通过(通道真的通了)', () async {
    final client = await doHello();
    server.acceptPendingPair();
    await doConfirm(client.key);

    final headers = await signHeaders(
      deviceId: 'client-1',
      sharedKey: client.key,
      method: 'GET',
      path: '/v1/hello',
      body: const [],
    );
    final res = await http.get(url('/v1/hello'), headers: headers);
    expect(res.statusCode, 200);
  });

  test('confirm 可重试(响应丢包场景):同参数二次调用仍 200 且不重复建行', () async {
    final client = await doHello();
    server.acceptPendingPair();
    expect((await doConfirm(client.key)).statusCode, 200);
    expect((await doConfirm(client.key)).statusCode, 200);
    expect((await db.watchPeers().first).length, 1);
  });

  test('用户拒绝 → 403,且 60 秒内同一设备再来直接被拒', () async {
    await doHello();
    server.rejectPendingPair();
    final res = await doConfirm(List<int>.filled(32, 0));
    expect(res.statusCode, 403);

    final again = await postHello();
    expect(again.statusCode, 403);
    expect(requests.length, 1); // 没有第二次骚扰用户
  });

  test('已有待确认配对时,别的设备来 hello → 429 busy', () async {
    await doHello();
    final other = await postHello(did: 'client-2', name: '平板');
    expect(other.statusCode, 429);
    expect(requests.length, 1);
  });

  test('待确认配对超时后自动清空,新设备可以再来', () async {
    await doHello();
    server.expirePendingPairForTest();
    final other = await postHello(did: 'client-2', name: '平板');
    expect(other.statusCode, 200);
    expect(requests.length, 2);
  });

  test('pubkey 不合法 → 400,不弹窗', () async {
    final res = await postHello(did: 'client-3', pubkey: '这不是 base64!!');
    expect(res.statusCode, 400);
    expect(requests, isEmpty);
  });
}
