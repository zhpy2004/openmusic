import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import 'discovery.dart';
import 'sync_server.dart';

/// mDNS 实现。**本项目唯一引用 bonsoir 的文件** —— 若它在某平台不可用,
/// 换掉这一个文件即可([Discovery] 抽象不动,见 spec §11 风险预案)。
///
/// 注:bonsoir 7.x 的 API 与老文档不同 —— 用 `initialize()`(不是 `ready`),
/// 事件是 sealed class(不是枚举),解析后的地址在 `service.hostAddresses`。
class BonsoirNetworkDiscovery implements Discovery {
  static const serviceType = '_openmusic._tcp';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  final _controller = StreamController<List<DiscoveredPeer>>.broadcast();

  /// 服务名 → 设备。用服务名做键是因为 lost 事件只带得到名字。
  final Map<String, DiscoveredPeer> _found = {};
  String? _myDeviceId;

  @override
  Stream<List<DiscoveredPeer>> get peers => _controller.stream;

  @override
  Future<void> start({
    required int port,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    _myDeviceId = deviceId;

    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: deviceName,
        type: serviceType,
        port: port,
        attributes: {
          'did': deviceId,
          'pv': '${SyncServer.protocolVersion}',
          'plat': platform,
        },
      ),
    );
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;

    final discovery = BonsoirDiscovery(type: serviceType);
    await discovery.initialize();
    _sub = discovery.eventStream?.listen(_onEvent);
    await discovery.start();
    _discovery = discovery;
  }

  Future<void> _onEvent(BonsoirDiscoveryEvent event) async {
    switch (event) {
      // found 只有名字,要 resolve 才拿得到地址与 TXT 记录。
      case BonsoirDiscoveryServiceFoundEvent():
        final resolver = _discovery?.serviceResolver;
        if (resolver != null) await event.service.resolve(resolver);
      case BonsoirDiscoveryServiceResolvedEvent():
        _remember(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        _remember(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        _found.remove(event.service.name);
        _emit();
      default:
        break;
    }
  }

  void _remember(BonsoirService service) {
    final did = service.attributes['did'];
    final host = service.hostAddresses.isEmpty
        ? null
        : service.hostAddresses.first;
    if (did == null || host == null) return;
    if (did == _myDeviceId) return; // 别把自己列进去
    _found[service.name] = DiscoveredPeer(
      deviceId: did,
      deviceName: service.name,
      platform: service.attributes['plat'] ?? 'unknown',
      protocolVersion: int.tryParse(service.attributes['pv'] ?? '') ?? 0,
      address: '$host:${service.port}',
    );
    _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(List.unmodifiable(_found.values));
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _discovery?.stop();
    _discovery = null;
    await _broadcast?.stop();
    _broadcast = null;
    _found.clear();
    _emit();
  }
}
