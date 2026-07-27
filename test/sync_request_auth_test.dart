import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/sync/request_auth.dart';

void main() {
  final key = List<int>.generate(32, (i) => i);
  final otherKey = List<int>.generate(32, (i) => 255 - i);
  final body = utf8.encode('{"hello":"world"}');
  const did = 'peer-1';

  Future<Map<String, String>> sign({
    String method = 'GET',
    String path = '/v1/hello',
    List<int>? withBody,
    DateTime? now,
  }) => signHeaders(
    deviceId: did,
    sharedKey: key,
    method: method,
    path: path,
    body: withBody ?? body,
    now: now,
  );

  Future<AuthFailure?> verify(
    Map<String, String> headers, {
    String method = 'GET',
    String path = '/v1/hello',
    List<int>? withBody,
    DateTime? now,
    List<int>? serverKey,
    ReplayGuard? guard,
  }) => verifyRequest(
    headers: headers,
    method: method,
    path: path,
    body: withBody ?? body,
    keyLookup: (id) async => id == did ? (serverKey ?? key) : null,
    guard: guard ?? ReplayGuard(),
    now: now,
  );

  test('正确签名验证通过', () async {
    expect(await verify(await sign()), isNull);
  });

  test('未知设备 → unknownDevice', () async {
    final h = await sign();
    h[headerDevice] = '不认识的设备';
    expect(await verify(h), AuthFailure.unknownDevice);
  });

  test('密钥不对 → badSignature', () async {
    expect(
      await verify(await sign(), serverKey: otherKey),
      AuthFailure.badSignature,
    );
  });

  test('篡改 path → badSignature', () async {
    expect(
      await verify(await sign(path: '/v1/hello'), path: '/v1/secret'),
      AuthFailure.badSignature,
    );
  });

  test('篡改 method → badSignature', () async {
    expect(
      await verify(await sign(method: 'GET'), method: 'POST'),
      AuthFailure.badSignature,
    );
  });

  test('篡改 body → badSignature', () async {
    expect(
      await verify(await sign(), withBody: utf8.encode('{"hello":"evil"}')),
      AuthFailure.badSignature,
    );
  });

  test('时间戳超出 5 分钟窗口 → clockSkew(两个方向都测)', () async {
    final base = DateTime.utc(2026, 7, 26, 12, 0, 0);
    final old = await sign(now: base.subtract(const Duration(minutes: 6)));
    expect(await verify(old, now: base), AuthFailure.clockSkew);

    final future = await sign(now: base.add(const Duration(minutes: 6)));
    expect(await verify(future, now: base), AuthFailure.clockSkew);
  });

  test('窗口边缘内(4 分钟)仍然通过', () async {
    final base = DateTime.utc(2026, 7, 26, 12, 0, 0);
    final h = await sign(now: base.subtract(const Duration(minutes: 4)));
    expect(await verify(h, now: base), isNull);
  });

  test('同一 nonce 二次使用 → replay', () async {
    final guard = ReplayGuard();
    final h = await sign();
    expect(await verify(h, guard: guard), isNull);
    expect(await verify(h, guard: guard), AuthFailure.replay);
  });

  test('缺少签名头 → badSignature(不崩)', () async {
    expect(await verify(const {}), AuthFailure.badSignature);
  });

  test('验签失败的请求不占用 nonce(否则可被提前"用掉")', () async {
    final guard = ReplayGuard();
    final h = await sign();
    // 用错误的服务端密钥验一次:必须失败,且不能记住这个 nonce
    expect(
      await verify(h, serverKey: otherKey, guard: guard),
      AuthFailure.badSignature,
    );
    // 合法请求随后仍应通过
    expect(await verify(h, guard: guard), isNull);
  });

  test('ReplayGuard 淘汰窗口外的 nonce,不无限增长', () {
    final base = DateTime.utc(2026, 7, 26, 12, 0, 0);
    final guard = ReplayGuard();
    for (var i = 0; i < 50; i++) {
      guard.checkAndRemember(
        'nonce-$i',
        base.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
        now: base,
      );
    }
    expect(guard.size, lessThanOrEqualTo(1));
  });
}
