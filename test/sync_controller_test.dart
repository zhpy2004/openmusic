import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/discovery.dart';
import 'package:openmusic/src/sync/sync_client.dart';
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

  group('refreshDiscovery', () {
    test('服务已起时,真的 stop 再 start 一轮,端口与身份透传', () async {
      await controller.start();
      final id = controller.identity!;
      final port = controller.serverPort;

      await controller.refreshDiscovery();

      expect(discovery.stopped, isTrue);
      expect(discovery.startCount, 2); // start() 一次 + refreshDiscovery 一次
      expect(
        discovery.startedWith,
        '$port/${id.deviceId}/${id.deviceName}/windows',
      );
    });

    test('服务没起来时直接返回,不做无谓的 stop/start', () async {
      await controller.refreshDiscovery();
      expect(discovery.stopCount, 0);
      expect(discovery.startCount, 0);
    });
  });

  group('runWithPeer', () {
    const peer = DiscoveredPeer(
      deviceId: 'peer1',
      deviceName: '手机',
      platform: 'android',
      protocolVersion: 1,
      address: '10.0.0.5:41517',
    );
    const rediscoveredPeer = DiscoveredPeer(
      deviceId: 'peer1',
      deviceName: '手机',
      platform: 'android',
      protocolVersion: 1,
      address: '10.0.0.5:44431',
    );

    test('地址过期后自动重新发现并重试一次,成功后返回结果', () async {
      await controller.start();
      discovery.emit(const [peer]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.addressOf('peer1'), peer.address);

      var calls = 0;
      final seenAddresses = <String>[];
      Future<String> action(String address) async {
        calls++;
        seenAddresses.add(address);
        if (calls == 1) {
          // 模拟"重新发现"这一轮真的拿到了对端的新地址。
          discovery.emit(const [rediscoveredPeer]);
          throw const SocketException('远程计算机拒绝网络连接');
        }
        return 'ok';
      }

      final result = await controller.runWithPeer(
        'peer1',
        action,
        discoveryPollInterval: const Duration(milliseconds: 10),
      );

      expect(result, 'ok');
      expect(calls, 2);
      expect(seenAddresses, [peer.address, rediscoveredPeer.address]);
      expect(discovery.stopped, isTrue); // refreshDiscovery 确实跑了
    });

    test('SyncAuthException 不重试,原样抛出', () async {
      await controller.start();
      discovery.emit(const [peer]);
      await Future<void>.delayed(Duration.zero);

      var calls = 0;
      Future<String> action(String address) async {
        calls++;
        throw const SyncAuthException('unknown_device');
      }

      await expectLater(
        () => controller.runWithPeer(
          'peer1',
          action,
          discoveryPollInterval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<SyncAuthException>()),
      );
      expect(calls, 1); // 解除配对后不该疯狂重新发现
      expect(discovery.stopped, isFalse);
    });

    test('SyncUnsupportedException 不重试,原样抛出', () async {
      await controller.start();
      discovery.emit(const [peer]);
      await Future<void>.delayed(Duration.zero);

      var calls = 0;
      Future<String> action(String address) async {
        calls++;
        throw const SyncUnsupportedException();
      }

      await expectLater(
        () => controller.runWithPeer(
          'peer1',
          action,
          discoveryPollInterval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<SyncUnsupportedException>()),
      );
      expect(calls, 1);
      expect(discovery.stopped, isFalse);
    });

    test('重新发现后地址没变,不重试,抛原异常', () async {
      await controller.start();
      discovery.emit(const [peer]);
      await Future<void>.delayed(Duration.zero);

      var calls = 0;
      Future<String> action(String address) async {
        calls++;
        throw const SocketException('远程计算机拒绝网络连接');
      }

      await expectLater(
        () => controller.runWithPeer(
          'peer1',
          action,
          discoveryWaitTimeout: const Duration(milliseconds: 50),
          discoveryPollInterval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 1); // 地址没变就不该再打第二次
      expect(discovery.stopped, isTrue); // 但确实尝试过重新发现
    });
  });
}
