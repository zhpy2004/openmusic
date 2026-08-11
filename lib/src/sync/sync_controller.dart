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
    await refreshDiscovery();
  }

  /// 强制重新发现:停掉再起一轮 mDNS,丢弃过期记录。
  ///
  /// 对端 App 重启后会拿到**新的随机端口**,而它若没来得及发 mDNS 告别包,
  /// 本机就会一直攥着旧地址。重起一轮发现是让缓存作废的最直接办法。
  Future<void> refreshDiscovery() async {
    final id = identity;
    final port = _server?.port;
    if (port == null || id == null) return; // 服务没起来,没什么可刷新的
    await discovery.stop();
    await discovery.start(
      port: port,
      deviceId: id.deviceId,
      deviceName: id.deviceName,
      platform: platform,
    );
  }

  /// 跑一个需要对端地址的动作;地址过期(连不上)时**自动重新发现并重试一次**。
  ///
  /// [SyncAuthException] / [SyncUnsupportedException] 不重试 —— 那是语义错误
  /// (已解除配对、对端版本太老),换个地址也一样,重试只会让用户多等。
  Future<T> runWithPeer<T>(
    String peerDeviceId,
    Future<T> Function(String address) action, {
    Duration discoveryWaitTimeout = const Duration(seconds: 3),
    Duration discoveryPollInterval = const Duration(milliseconds: 200),
  }) async {
    final address = await _resolvePeerAddress(peerDeviceId);
    try {
      return await action(address);
    } on SyncAuthException {
      rethrow;
    } on SyncUnsupportedException {
      rethrow;
    } catch (_) {
      await refreshDiscovery();
      final newAddress = await _waitForAddressChange(
        peerDeviceId,
        address,
        timeout: discoveryWaitTimeout,
        pollInterval: discoveryPollInterval,
      );
      // 重新发现后地址没变(或压根没等到):再重试也是白等,抛原异常。
      if (newAddress == null) rethrow;
      return await action(newAddress);
    }
  }

  /// 优先取 mDNS 实时地址,没有就退回库里记的上次联系地址。
  Future<String> _resolvePeerAddress(String peerDeviceId) async {
    final live = addressOf(peerDeviceId);
    if (live != null) return live;
    final peer = await db.getPeer(peerDeviceId);
    final last = peer?.lastAddress;
    if (last != null) return last;
    throw StateError('设备 $peerDeviceId 没有可用地址(未在局域网中发现)');
  }

  /// 轮询等待发现层给出一个与 [oldAddress] 不同的新地址;超时返回 null。
  /// 用 `Future.delayed` 让出事件循环,不忙等、不卡 UI 线程。
  Future<String?> _waitForAddressChange(
    String peerDeviceId,
    String oldAddress, {
    required Duration timeout,
    required Duration pollInterval,
  }) async {
    var waited = Duration.zero;
    while (waited < timeout) {
      await Future<void>.delayed(pollInterval);
      waited += pollInterval;
      final addr = addressOf(peerDeviceId);
      if (addr != null && addr != oldAddress) return addr;
    }
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _client?.close();
    super.dispose();
  }
}
