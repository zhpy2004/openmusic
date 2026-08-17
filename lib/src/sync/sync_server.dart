import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import 'metadata_merge.dart';
import 'pair_crypto.dart';
import 'request_auth.dart';
import 'sync_payload.dart';

/// 收到配对请求时交给 UI 的信息。UI 显示 [code] 并等用户确认。
class PairRequest {
  const PairRequest({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.code,
  });
  final String deviceId;
  final String deviceName;
  final String platform;
  final String code;
}

enum _PairDecision { pending, accepted, rejected }

class _PendingPair {
  _PendingPair({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.sharedKey,
    required this.code,
    required this.createdAt,
  });
  final String deviceId;
  final String deviceName;
  final String platform;
  final List<int> sharedKey;
  final String code;
  final DateTime createdAt;
  _PairDecision decision = _PairDecision.pending;
}

/// 本机同步服务。绑 0.0.0.0:0 让系统分配端口(随 mDNS 播报),
/// 不钉固定端口——Windows 防火墙按程序而非端口授权,随机端口无额外代价。
class SyncServer {
  SyncServer({
    required this.db,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.trackCount,
    this.onPairRequest,
    this.enableMetadataSyncForTest = true,
  });

  /// 仅测试:置 false 可模拟"对端是只有 M3-A 的老版本"(该路径返回 404)。
  final bool enableMetadataSyncForTest;

  static const protocolVersion = 1;

  /// 待确认配对的有效期:与发起方的重试超时一致。
  static const pairWindow = Duration(seconds: 60);

  /// 被拒后的冷却期,防止免签名端点被反复骚扰。
  static const rejectCooldown = Duration(seconds: 60);

  final AppDatabase db;
  final String deviceId;
  final String deviceName;
  final String platform;
  final Future<int> Function() trackCount;

  /// 收到配对请求时通知 UI 弹窗(显示 6 位码 + 确认/拒绝)。
  final void Function(PairRequest request)? onPairRequest;

  final ReplayGuard _guard = ReplayGuard();
  HttpServer? _http;

  _PendingPair? _pending;
  final Map<String, DateTime> _rejectedUntil = {};

  int? get port => _http?.port;
  bool get isRunning => _http != null;

  /// UI 上用户点「两边数字一致」。
  void acceptPendingPair() => _pending?.decision = _PairDecision.accepted;

  /// UI 上用户点「拒绝」。同一设备进入冷却期。
  void rejectPendingPair() {
    final p = _pending;
    if (p == null) return;
    p.decision = _PairDecision.rejected;
    _rejectedUntil[p.deviceId] = DateTime.now().add(rejectCooldown);
  }

  /// 当前待确认的配对(UI 用来判断该不该显示弹窗)。
  PairRequest? get pendingPair {
    final p = _pending;
    if (p == null || _isExpired(p)) return null;
    if (p.decision != _PairDecision.pending) return null;
    return PairRequest(
      deviceId: p.deviceId,
      deviceName: p.deviceName,
      platform: p.platform,
      code: p.code,
    );
  }

  bool _isExpired(_PendingPair p) =>
      DateTime.now().difference(p.createdAt) > pairWindow;

  /// 仅供测试:把待确认配对立即作废,免得测试等 60 秒。
  @visibleForTesting
  void expirePendingPairForTest() => _pending = null;

  Future<int> start({int port = 0}) async {
    if (_http != null) return _http!.port;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _http = server;
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<void> stop() async {
    final server = _http;
    _http = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final body = await _readBody(req);
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/v1/hello') {
        await _handleHello(req, body);
        return;
      }
      if (req.method == 'POST' && path == '/v1/pair/hello') {
        await _handlePairHello(req, body);
        return;
      }
      if (req.method == 'POST' && path == '/v1/pair/confirm') {
        await _handlePairConfirm(req, body);
        return;
      }
      if (req.method == 'POST' &&
          path == '/v1/sync/metadata' &&
          enableMetadataSyncForTest) {
        await _handleMetadataSync(req, body);
        return;
      }
      await _respond(req, 404, {'error': 'not_found'});
    } catch (e) {
      // 单个请求失败绝不能带倒服务(母 spec §8)。
      await _respond(req, 500, {'error': e.toString()});
    }
  }

  Future<List<int>> _readBody(HttpRequest req) async {
    final chunks = <int>[];
    await for (final chunk in req) {
      chunks.addAll(chunk);
    }
    return chunks;
  }

  Map<String, String> _headersOf(HttpRequest req) {
    final map = <String, String>{};
    req.headers.forEach((name, values) {
      if (values.isNotEmpty) map[name.toLowerCase()] = values.first;
    });
    return map;
  }

  /// 验签;通过返回 null,否则已经把 401 写回去了。
  Future<AuthFailure?> _authorize(HttpRequest req, List<int> body) async {
    final failure = await verifyRequest(
      headers: _headersOf(req),
      method: req.method,
      path: req.uri.path,
      body: body,
      keyLookup: (id) async {
        final peer = await db.getPeer(id);
        return peer == null ? null : base64.decode(peer.sharedKey);
      },
      guard: _guard,
    );
    if (failure != null) {
      await _respond(req, 401, {'reason': failure.wireName});
    }
    return failure;
  }

  Future<void> _handleHello(HttpRequest req, List<int> body) async {
    if (await _authorize(req, body) != null) return;
    await _respond(req, 200, {
      'did': deviceId,
      'name': deviceName,
      'plat': platform,
      'pv': protocolVersion,
      'trackCount': await trackCount(),
    });
  }

  /// 唯一免签名端点 —— 因此必须自带防滥用:
  /// 同一时刻只保留一个待确认配对(其余 429),被拒设备 60 秒内一律 403。
  Future<void> _handlePairHello(HttpRequest req, List<int> body) async {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    } catch (_) {
      await _respond(req, 400, {'error': 'bad_request'});
      return;
    }
    final theirId = json['did'] as String?;
    final theirName = json['name'] as String?;
    final theirPlat = json['plat'] as String?;
    final pubkeyRaw = json['pubkey'] as String?;
    if (theirId == null ||
        theirName == null ||
        theirPlat == null ||
        pubkeyRaw == null) {
      await _respond(req, 400, {'error': 'bad_request'});
      return;
    }

    final until = _rejectedUntil[theirId];
    if (until != null && DateTime.now().isBefore(until)) {
      await _respond(req, 403, {'reason': 'rejected'});
      return;
    }

    final current = _pending;
    if (current != null &&
        !_isExpired(current) &&
        current.decision == _PairDecision.pending &&
        current.deviceId != theirId) {
      await _respond(req, 429, {'reason': 'busy'});
      return;
    }

    final List<int> theirPub;
    try {
      theirPub = base64.decode(pubkeyRaw);
      if (theirPub.length != 32) throw const FormatException('bad length');
    } catch (_) {
      await _respond(req, 400, {'error': 'bad_pubkey'});
      return;
    }

    final myKeys = await generatePairKeys();
    final List<int> sharedKey;
    try {
      sharedKey = await deriveSharedKey(
        myKeyPair: myKeys.keyPair,
        theirPublicKey: theirPub,
        myDeviceId: deviceId,
        theirDeviceId: theirId,
      );
    } catch (_) {
      await _respond(req, 400, {'error': 'bad_pubkey'});
      return;
    }
    final code = await pairingCode(sharedKey, deviceId, theirId);

    _pending = _PendingPair(
      deviceId: theirId,
      deviceName: theirName,
      platform: theirPlat,
      sharedKey: sharedKey,
      code: code,
      createdAt: DateTime.now(),
    );
    onPairRequest?.call(
      PairRequest(
        deviceId: theirId,
        deviceName: theirName,
        platform: theirPlat,
        code: code,
      ),
    );

    await _respond(req, 200, {
      'did': deviceId,
      'name': deviceName,
      'plat': platform,
      'pv': protocolVersion,
      'pubkey': base64.encode(myKeys.publicKeyBytes),
    });
  }

  /// 落库时机是刻意的:被连方点"确认"只改内存状态,**两端真正写 peers 都由
  /// 这个请求触发** —— 不会出现"B 已配对而 A 没有"的单边状态。
  ///
  /// 成功后**不清空 `_pending`**:发起方没收到 200(丢包)会用新 nonce 重试,
  /// 清掉就变成 409 expired,正是 spec §8 要避免的残留窗口。
  Future<void> _handlePairConfirm(HttpRequest req, List<int> body) async {
    final pending = _pending;
    if (pending == null || _isExpired(pending)) {
      await _respond(req, 409, {'reason': 'expired'});
      return;
    }
    if (pending.decision == _PairDecision.rejected) {
      await _respond(req, 403, {'reason': 'rejected'});
      return;
    }
    if (pending.decision == _PairDecision.pending) {
      await _respond(req, 409, {'reason': 'pending'});
      return;
    }

    // 已确认:此刻才用协商出的密钥验签,证明对面确实是握手的那一方。
    final failure = await verifyRequest(
      headers: _headersOf(req),
      method: req.method,
      path: req.uri.path,
      body: body,
      keyLookup: (id) async => id == pending.deviceId ? pending.sharedKey : null,
      guard: _guard,
    );
    if (failure != null) {
      await _respond(req, 401, {'reason': failure.wireName});
      return;
    }

    await db.upsertPeer(
      deviceId: pending.deviceId,
      deviceName: pending.deviceName,
      platform: pending.platform,
      sharedKey: base64.encode(pending.sharedKey),
    );
    final remote = req.connectionInfo?.remoteAddress.address;
    if (remote != null) {
      await db.recordPeerContact(pending.deviceId, address: remote);
    }
    await _respond(req, 200, {'did': deviceId, 'name': deviceName});
  }

  /// 收到对端全量快照 → 合并进本机 → **把本机合并后的快照回给对端**。
  /// 一次往返双向完成;重复调用只是把同样的合并再算一遍,天然幂等。
  Future<void> _handleMetadataSync(HttpRequest req, List<int> body) async {
    if (await _authorize(req, body) != null) return;

    final MetadataSnapshot remote;
    try {
      remote = MetadataSnapshot.fromJson(
        jsonDecode(utf8.decode(body)) as Map<String, dynamic>,
      );
    } catch (_) {
      // 解析失败整轮拒绝,不做部分应用——半懂的数据比不同步更危险。
      await _respond(req, 400, {'error': 'bad_snapshot'});
      return;
    }

    final local = await db.readSyncSnapshot(deviceId);
    await db.applySyncChanges(mergeMetadata(local: local, remote: remote));

    final merged = await db.readSyncSnapshot(deviceId);
    await _respond(req, 200, merged.toJson());
  }

  Future<void> _respond(
    HttpRequest req,
    int status,
    Map<String, dynamic> body,
  ) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }
}
