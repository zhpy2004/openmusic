import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import 'device_identity.dart';
import 'discovery.dart';
import 'sync_client.dart';
import 'sync_server.dart';

/// 编排同步服务的生命周期与 UI 状态。
///
/// 生命周期跟随 App 前台(裁决 2):[start] 起 HttpServer + mDNS,
/// [stop] 全部停。不做常驻后台。
class SyncController extends ChangeNotifier {
  SyncController({
    required this.db,
    required this.discovery,
    required this.platform,
    this.buildServer,
    this.buildClient,
  });

  final AppDatabase db;
  final Discovery discovery;
  final String platform;

  /// 测试注入点:不传则用真实的 [SyncServer] / [SyncClient]。
  final SyncServer Function(DeviceIdentity identity)? buildServer;
  final SyncClient Function(DeviceIdentity identity)? buildClient;

  DeviceIdentity? identity;
  SyncServer? _server;
  SyncClient? _client;
  StreamSubscription<List<DiscoveredPeer>>? _sub;

  /// 最近一次 mDNS 快照(内存态,不落库)。
  List<DiscoveredPeer> online = const [];

  /// 服务启动失败的原因;非 null 时 UI 显示红条 + 重试按钮。
  String? startError;

  /// 待确认的配对请求(对方发起,本机需弹窗)。
  PairRequest? incomingPair;

  int? get serverPort => _server?.port;
  SyncClient? get client => _client;

  Future<void> start() async {
    if (_server != null) return; // 幂等
    startError = null;
    try {
      final id = await loadOrCreateIdentity(db);
      identity = id;
      final server =
          buildServer?.call(id) ??
          SyncServer(
            db: db,
            deviceId: id.deviceId,
            deviceName: id.deviceName,
            platform: platform,
            trackCount: () async => (await db.watchTracks('').first).length,
            onPairRequest: _onIncomingPair,
          );
      final port = await server.start();
      _server = server;
      _client =
          buildClient?.call(id) ??
          SyncClient(
            db: db,
            deviceId: id.deviceId,
            deviceName: id.deviceName,
            platform: platform,
          );
      _sub = discovery.peers.listen((list) {
        online = list;
        notifyListeners();
      });
      await discovery.start(
        port: port,
        deviceId: id.deviceId,
        deviceName: id.deviceName,
        platform: platform,
      );
    } catch (e) {
      // 同步服务起不来绝不能影响播放与曲库(母 spec §8)。
      startError = e.toString();
      _server = null;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await discovery.stop();
    await _server?.stop();
    _server = null;
    _client?.close();
    _client = null;
    online = const [];
    notifyListeners();
  }

  void _onIncomingPair(PairRequest request) {
    incomingPair = request;
    notifyListeners();
  }

  void acceptIncomingPair() {
    _server?.acceptPendingPair();
    incomingPair = null;
    notifyListeners();
  }

  void rejectIncomingPair() {
    _server?.rejectPendingPair();
    incomingPair = null;
    notifyListeners();
  }

  /// 在线但尚未配对的设备 —— 同步页「局域网内发现」区的数据源。
  Future<List<DiscoveredPeer>> pairableDevices() async {
    final paired = await db.watchPeers().first;
    final pairedIds = paired.map((p) => p.deviceId).toSet();
    return online.where((p) => !pairedIds.contains(p.deviceId)).toList();
  }

  /// 某设备当前的局域网地址;不在线返回 null(UI 据此置灰「测试连接」)。
  String? addressOf(String deviceId) {
    for (final peer in online) {
      if (peer.deviceId == deviceId) return peer.address;
    }
    return null;
  }

  /// 改设备名。广播里带着旧名字,故重起一轮发现层让对端看到新名字。
  Future<void> renameLocalDevice(String name) async {
    final current = identity;
    if (current == null) return;
    await db.setLocalDeviceName(name);
    identity = DeviceIdentity(deviceId: current.deviceId, deviceName: name);
    notifyListeners();
    final port = _server?.port;
    if (port == null) return;
    await discovery.stop();
    await discovery.start(
      port: port,
      deviceId: current.deviceId,
      deviceName: name,
      platform: platform,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _client?.close();
    super.dispose();
  }
}
