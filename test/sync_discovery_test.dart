import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/sync/discovery.dart';

import 'helpers/fake_discovery.dart';

void main() {
  test('Fake 推送的设备原样出现在流里', () async {
    final d = FakeDiscovery();
    await d.start(
      port: 5000,
      deviceId: 'me',
      deviceName: '本机',
      platform: 'windows',
    );
    expect(d.startedWith, '5000/me/本机/windows');

    final seen = <List<DiscoveredPeer>>[];
    final sub = d.peers.listen(seen.add);
    d.emit([
      const DiscoveredPeer(
        deviceId: 'them',
        deviceName: '手机',
        platform: 'android',
        protocolVersion: 1,
        address: '192.168.1.9:52341',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(seen.single.single.deviceName, '手机');
    await sub.cancel();
    await d.stop();
    expect(d.stopped, isTrue);
    d.dispose();
  });

  test('DiscoveredPeer 值相等(列表 diff 用得上)', () {
    const a = DiscoveredPeer(
      deviceId: 'x',
      deviceName: 'n',
      platform: 'android',
      protocolVersion: 1,
      address: '1.2.3.4:5',
    );
    const b = DiscoveredPeer(
      deviceId: 'x',
      deviceName: 'n',
      platform: 'android',
      protocolVersion: 1,
      address: '1.2.3.4:5',
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('协议版本不同的设备可被识别出来', () {
    const peer = DiscoveredPeer(
      deviceId: 'x',
      deviceName: 'n',
      platform: 'android',
      protocolVersion: 99,
      address: '1.2.3.4:5',
    );
    expect(peer.isCompatible, isFalse);
  });
}
