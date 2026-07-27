import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(testExecutor()));
  tearDown(() => db.close());

  test('本机身份单行:重复 ensure 不覆盖已有值', () async {
    await db.ensureLocalDevice(deviceId: 'aabb', deviceName: 'PC');
    await db.ensureLocalDevice(deviceId: 'cccc', deviceName: '别的');
    final d = await db.getLocalDevice();
    expect(d!.deviceId, 'aabb');
    expect(d.deviceName, 'PC');
  });

  test('设备名可改,deviceId 不变', () async {
    await db.ensureLocalDevice(deviceId: 'aabb', deviceName: 'PC');
    await db.setLocalDeviceName('书房台式机');
    final d = await db.getLocalDevice();
    expect(d!.deviceId, 'aabb');
    expect(d.deviceName, '书房台式机');
  });

  test('配对写入后可按 deviceId 取回密钥', () async {
    await db.upsertPeer(
      deviceId: 'peer1',
      deviceName: '手机',
      platform: 'android',
      sharedKey: 'a2V5',
    );
    final p = await db.getPeer('peer1');
    expect(p!.sharedKey, 'a2V5');
    expect(p.deviceName, '手机');
    expect(p.pairedAt, greaterThan(0));
  });

  test('重复配对是更新而非新增,且 pairedAt 保留首次值', () async {
    await db.upsertPeer(
      deviceId: 'peer1',
      deviceName: '手机',
      platform: 'android',
      sharedKey: 'k1',
    );
    final first = (await db.getPeer('peer1'))!.pairedAt;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await db.upsertPeer(
      deviceId: 'peer1',
      deviceName: '手机改名',
      platform: 'android',
      sharedKey: 'k2',
    );
    final all = await db.watchPeers().first;
    expect(all.length, 1);
    expect(all.single.sharedKey, 'k2');
    expect(all.single.deviceName, '手机改名');
    expect(all.single.pairedAt, first);
  });

  test('联系信息只在显式调用时写,不随配对写入', () async {
    await db.upsertPeer(
      deviceId: 'peer1',
      deviceName: '手机',
      platform: 'android',
      sharedKey: 'k',
    );
    expect((await db.getPeer('peer1'))!.lastAddress, isNull);
    await db.recordPeerContact('peer1', address: '192.168.1.9:52341');
    final p = (await db.getPeer('peer1'))!;
    expect(p.lastAddress, '192.168.1.9:52341');
    expect(p.lastContactAt, greaterThan(0));
  });

  test('解除配对删除该行', () async {
    await db.upsertPeer(
      deviceId: 'peer1',
      deviceName: '手机',
      platform: 'android',
      sharedKey: 'k',
    );
    await db.deletePeer('peer1');
    expect(await db.getPeer('peer1'), isNull);
    expect(await db.watchPeers().first, isEmpty);
  });
}
