import 'dart:async';

import 'package:openmusic/src/sync/discovery.dart';

/// 测试用发现层:手动 emit 设备列表,记录 start 参数。
class FakeDiscovery implements Discovery {
  final _controller = StreamController<List<DiscoveredPeer>>.broadcast();
  String? startedWith;
  bool stopped = false;

  /// start()/stop() 各被调用了几次 —— 用来断言"重新发现真的重起了一轮"。
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<List<DiscoveredPeer>> get peers => _controller.stream;

  @override
  Future<void> start({
    required int port,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    startedWith = '$port/$deviceId/$deviceName/$platform';
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    stopCount++;
  }

  void emit(List<DiscoveredPeer> list) => _controller.add(list);

  void dispose() => _controller.close();
}
