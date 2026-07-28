import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/database.dart';
import 'pair_crypto.dart';
import 'request_auth.dart';
import 'sync_server.dart';

enum PairOutcome { paired, rejected, timedOut, failed }

/// 对端拒绝了我们的签名(401)。[reason] 是 wire 上的原因串,UI 据此给文案。
class SyncAuthException implements Exception {
  const SyncAuthException(this.reason);
  final String reason;
  @override
  String toString() => 'SyncAuthException($reason)';
}

/// 对端返回了非 200/401 的状态码,或传输本身出了问题。
class SyncTransportException implements Exception {
  const SyncTransportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `/v1/hello` 的响应。
class HelloResult {
  const HelloResult({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.protocolVersion,
    required this.trackCount,
  });
  final String deviceId;
  final String deviceName;
  final String platform;
  final int protocolVersion;
  final int trackCount;
}

class SyncClient {
  SyncClient({
    required this.db,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final AppDatabase db;
  final String deviceId;
  final String deviceName;
  final String platform;
  final http.Client _http;

  /// 单次请求超时。不做指数退避重试——局域网内失败就是失败,
  /// 反复重试只会让 UI 卡住(母 spec §8:不做重试风暴)。
  static const requestTimeout = Duration(seconds: 5);

  void close() => _http.close();

  /// 与 [address]("ip:port")完成配对。[onCode] 一拿到 6 位码就回调给 UI 显示,
  /// 之后本方法轮询对端的确认状态直到 200/403/超时。
  Future<PairOutcome> pair({
    required String address,
    required void Function(String code) onCode,
    Duration timeout = SyncServer.pairWindow,
    Duration retryInterval = const Duration(seconds: 1),
  }) async {
    try {
      final myKeys = await generatePairKeys();
      final helloRes = await _http
          .post(
            Uri.parse('http://$address/v1/pair/hello'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'did': deviceId,
              'name': deviceName,
              'plat': platform,
              'pubkey': base64.encode(myKeys.publicKeyBytes),
            }),
          )
          .timeout(requestTimeout);
      if (helloRes.statusCode == 403) return PairOutcome.rejected;
      if (helloRes.statusCode != 200) return PairOutcome.failed;

      final body = jsonDecode(helloRes.body) as Map<String, dynamic>;
      final theirId = body['did'] as String;
      final sharedKey = await deriveSharedKey(
        myKeyPair: myKeys.keyPair,
        theirPublicKey: base64.decode(body['pubkey'] as String),
        myDeviceId: deviceId,
        theirDeviceId: theirId,
      );
      onCode(await pairingCode(sharedKey, deviceId, theirId));

      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        final payload = utf8.encode(jsonEncode({'did': deviceId}));
        final headers = await signHeaders(
          deviceId: deviceId,
          sharedKey: sharedKey,
          method: 'POST',
          path: '/v1/pair/confirm',
          body: payload,
        );
        final res = await _http
            .post(
              Uri.parse('http://$address/v1/pair/confirm'),
              headers: {...headers, 'content-type': 'application/json'},
              body: payload,
            )
            .timeout(requestTimeout);
        if (res.statusCode == 200) {
          await db.upsertPeer(
            deviceId: theirId,
            deviceName: body['name'] as String,
            platform: body['plat'] as String,
            sharedKey: base64.encode(sharedKey),
          );
          await db.recordPeerContact(theirId, address: address);
          return PairOutcome.paired;
        }
        if (res.statusCode == 403) return PairOutcome.rejected;
        if (res.statusCode != 409) return PairOutcome.failed;
        await Future<void>.delayed(retryInterval);
      }
      return PairOutcome.timedOut;
    } catch (_) {
      // 网络不可达/超时/对端不是 openmusic:都归为 failed,由 UI 提示。
      return PairOutcome.failed;
    }
  }

  /// 对已配对设备打 `/v1/hello`。成功时顺带记录联系地址与时间。
  Future<HelloResult> hello({
    required String peerDeviceId,
    String? address,
  }) async {
    final peer = await db.getPeer(peerDeviceId);
    if (peer == null) {
      throw StateError('设备 $peerDeviceId 尚未配对');
    }
    final target = address ?? peer.lastAddress;
    if (target == null) {
      throw StateError('设备 $peerDeviceId 没有可用地址(未在局域网中发现)');
    }
    final key = base64.decode(peer.sharedKey);
    final headers = await signHeaders(
      deviceId: deviceId,
      sharedKey: key,
      method: 'GET',
      path: '/v1/hello',
      body: const [],
    );
    final res = await _http
        .get(Uri.parse('http://$target/v1/hello'), headers: headers)
        .timeout(requestTimeout);
    if (res.statusCode == 401) {
      final reason = jsonDecode(res.body)['reason'] as String? ?? 'unknown';
      throw SyncAuthException(reason);
    }
    if (res.statusCode != 200) {
      throw SyncTransportException('对端返回 ${res.statusCode}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    await db.recordPeerContact(peerDeviceId, address: target);
    return HelloResult(
      deviceId: body['did'] as String,
      deviceName: body['name'] as String,
      platform: body['plat'] as String,
      protocolVersion: body['pv'] as int,
      trackCount: body['trackCount'] as int? ?? 0,
    );
  }
}
