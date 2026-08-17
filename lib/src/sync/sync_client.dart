import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/database.dart';
import 'metadata_merge.dart';
import 'pair_crypto.dart';
import 'request_auth.dart';
import 'sync_payload.dart';
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

/// 对端没有元数据同步端点 —— 它还是只有 M3-A 的老版本。
class SyncUnsupportedException implements Exception {
  const SyncUnsupportedException();
  @override
  String toString() => 'SyncUnsupportedException';
}

/// 一次同步在**本地**实际produced的变更数,直接用于 UI 摘要。
class SyncSummary {
  const SyncSummary({
    required this.playlists,
    required this.playlistItems,
    required this.favorites,
    required this.overrides,
    required this.playEvents,
  });

  final int playlists;
  final int playlistItems;
  final int favorites;
  final int overrides;
  final int playEvents;

  bool get isEmpty =>
      playlists == 0 &&
      playlistItems == 0 &&
      favorites == 0 &&
      overrides == 0 &&
      playEvents == 0;
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

  /// 与已配对设备做一轮元数据同步。返回**本地实际发生的变更数**。
  Future<SyncSummary> syncMetadata({
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

    final local = await db.readSyncSnapshot(deviceId);
    final payload = utf8.encode(jsonEncode(local.toJson()));
    final headers = await signHeaders(
      deviceId: deviceId,
      sharedKey: key,
      method: 'POST',
      path: '/v1/sync/metadata',
      body: payload,
    );
    final res = await _http
        .post(
          Uri.parse('http://$target/v1/sync/metadata'),
          headers: {...headers, 'content-type': 'application/json'},
          body: payload,
        )
        .timeout(requestTimeout);

    if (res.statusCode == 404) throw const SyncUnsupportedException();
    if (res.statusCode == 401) {
      final reason = jsonDecode(res.body)['reason'] as String? ?? 'unknown';
      throw SyncAuthException(reason);
    }
    if (res.statusCode != 200) {
      throw SyncTransportException('对端返回 ${res.statusCode}');
    }

    final remote = MetadataSnapshot.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
    // 对端已经把我们的快照合并过了,这里合并的是它合并后的状态 → 两端收敛。
    final result = mergeMetadata(
      local: await db.readSyncSnapshot(deviceId),
      remote: remote,
    );
    await db.applySyncChanges(result);
    await db.recordPeerContact(peerDeviceId, address: target);

    return SyncSummary(
      playlists: result.playlists.length,
      playlistItems: result.playlistItems.length,
      favorites: result.favorites.length,
      overrides: result.overrides.length,
      playEvents: result.playEvents.length,
    );
  }
}
