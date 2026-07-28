import 'sync_server.dart';

/// mDNS 上看到的一台设备。**不落库** —— 在线状态来自实时流,
/// 写库会让每次发现 tick 触发 drift 表级流失效风暴。
class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.protocolVersion,
    required this.address,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final int protocolVersion;

  /// "ip:port"
  final String address;

  /// 协议版本对不上就别握手,UI 标注"需要升级 openmusic"。
  bool get isCompatible => protocolVersion == SyncServer.protocolVersion;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPeer &&
      other.deviceId == deviceId &&
      other.deviceName == deviceName &&
      other.platform == platform &&
      other.protocolVersion == protocolVersion &&
      other.address == address;

  @override
  int get hashCode =>
      Object.hash(deviceId, deviceName, platform, protocolVersion, address);
}

/// 设备发现。实现可以是 mDNS(bonsoir),也可以是测试用的 Fake。
abstract class Discovery {
  /// 开始广播本机并监听同类服务。
  Future<void> start({
    required int port,
    required String deviceId,
    required String deviceName,
    required String platform,
  });

  Future<void> stop();

  /// 当前在线设备的完整列表(每次变化推送一份全量快照)。
  Stream<List<DiscoveredPeer>> get peers;
}
