import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/discovery.dart';
import 'package:openmusic/src/sync/sync_controller.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';
import 'helpers/fake_discovery.dart';

class _StubException implements Exception {
  const _StubException(this.message);
  final String message;
  @override
  String toString() => message;
}

void main() {
  late AppDatabase db;
  late FakeDiscovery discovery;
  late SyncController controller;

  setUp(() {
    db = AppDatabase(testExecutor());
    discovery = FakeDiscovery();
    controller = SyncController(
      db: db,
      discovery: discovery,
      platform: 'windows',
      buildServer: (identity) => SyncServer(
        db: db,
        deviceId: identity.deviceId,
        deviceName: identity.deviceName,
        platform: 'windows',
        trackCount: () async => 0,
      ),
    );
  });

  tearDown(() async {
    await controller.stop();
    controller.dispose();
    discovery.dispose();
    await db.close();
  });

  test('start 生成身份、起服务、把端口传给发现层', () async {
    await controller.start();
    expect(controller.identity!.deviceId, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(controller.serverPort, greaterThan(0));
    expect(discovery.startedWith, contains('${controller.serverPort}'));
    expect(controller.startError, isNull);
  });

  test('stop 停服务与发现层,端口清空', () async {
    await controller.start();
    await controller.stop();
    expect(controller.serverPort, isNull);
    expect(discovery.stopped, isTrue);
  });

  test('重复 start 幂等,不会起两个服务', () async {
    await controller.start();
    final port = controller.serverPort;
    await controller.start();
    expect(controller.serverPort, port);
  });

  test('发现到的设备里,已配对的被过滤出"可配对"列表', () async {
    await controller.start();
    await db.upsertPeer(
      deviceId: 'known',
      deviceName: '老朋友',
      platform: 'android',
      sharedKey: 'k',
    );
    discovery.emit(const [
      DiscoveredPeer(
        deviceId: 'known',
        deviceName: '老朋友',
        platform: 'android',
        protocolVersion: 1,
        address: '10.0.0.2:1111',
      ),
      DiscoveredPeer(
        deviceId: 'stranger',
        deviceName: '新设备',
        platform: 'android',
        protocolVersion: 1,
        address: '10.0.0.3:2222',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    final pairable = await controller.pairableDevices();
    expect(pairable.map((p) => p.deviceId), ['stranger']);
    expect(controller.addressOf('known'), '10.0.0.2:1111');
    expect(controller.addressOf('从没见过'), isNull);
  });

  test('服务起不来时记录错误而不抛(不能带倒 App)', () async {
    final failing = SyncController(
      db: db,
      discovery: discovery,
      platform: 'windows',
      buildServer: (_) => throw const _StubException('端口被占用'),
    );
    await failing.start();
    expect(failing.startError, contains('端口被占用'));
    expect(failing.serverPort, isNull);
    failing.dispose();
  });

  test('改设备名后重启广播,身份 id 不变', () async {
    await controller.start();
    final id = controller.identity!.deviceId;
    await controller.renameLocalDevice('书房台式机');
    expect(controller.identity!.deviceName, '书房台式机');
    expect(controller.identity!.deviceId, id);
    expect((await db.getLocalDevice())!.deviceName, '书房台式机');
    expect(discovery.startedWith, contains('书房台式机'));
  });
}
