// 只要 driftRuntimeOptions 一个符号;drift 与 matcher 有多个同名导出
// (isNull / isNotNull 等),用 show 精确引入最省事。
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/sync_client.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';

void main() {
  // 本文件刻意同时开两个 AppDatabase(模拟两台设备),但它们各自持有**不同的**
  // 内存库 executor,不存在 drift 警告所指的共享 executor 竞态。关掉这条启发式
  // 警告,否则每个用例刷一屏栈,真问题会被淹没。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase dbA; // 发起方
  late AppDatabase dbB; // 被连方
  late SyncServer serverA;
  late SyncServer serverB;
  late SyncClient clientA;
  final pairRequestsOnB = <PairRequest>[];

  setUp(() async {
    pairRequestsOnB.clear();
    dbA = AppDatabase(testExecutor());
    dbB = AppDatabase(testExecutor());
    serverA = SyncServer(
      db: dbA,
      deviceId: 'device-a',
      deviceName: '台式机',
      platform: 'windows',
      trackCount: () async => 116,
    );
    serverB = SyncServer(
      db: dbB,
      deviceId: 'device-b',
      deviceName: '手机',
      platform: 'android',
      trackCount: () async => 42,
      onPairRequest: pairRequestsOnB.add,
    );
    await serverA.start();
    await serverB.start();
    clientA = SyncClient(
      db: dbA,
      deviceId: 'device-a',
      deviceName: '台式机',
      platform: 'windows',
    );
  });

  tearDown(() async {
    clientA.close();
    await serverA.stop();
    await serverB.stop();
    await dbA.close();
    await dbB.close();
  });

  String addressB() => '127.0.0.1:${serverB.port}';

  test('完整配对:两端看到同一个码,确认后各自落库', () async {
    String? codeOnA;
    final outcome = await clientA.pair(
      address: addressB(),
      onCode: (code) {
        codeOnA = code;
        serverB.acceptPendingPair(); // 模拟 B 侧用户点确认
      },
      retryInterval: const Duration(milliseconds: 10),
    );

    expect(outcome, PairOutcome.paired);
    expect(codeOnA, isNotNull);
    expect(pairRequestsOnB.single.code, codeOnA);

    final onA = await dbA.getPeer('device-b');
    final onB = await dbB.getPeer('device-a');
    expect(onA!.deviceName, '手机');
    expect(onB!.deviceName, '台式机');
    expect(onA.sharedKey, onB.sharedKey); // 同一把密钥
    expect(onA.lastAddress, addressB()); // 发起方记住了对端地址
  });

  test('配对后 hello 拿到对端信息并更新联系时间', () async {
    await clientA.pair(
      address: addressB(),
      onCode: (_) => serverB.acceptPendingPair(),
      retryInterval: const Duration(milliseconds: 10),
    );
    final result = await clientA.hello(peerDeviceId: 'device-b');
    expect(result.deviceName, '手机');
    expect(result.platform, 'android');
    expect(result.trackCount, 42);
    expect(result.protocolVersion, 1);
    expect((await dbA.getPeer('device-b'))!.lastContactAt, isNotNull);
  });

  test('对端拒绝 → rejected,两端都不落库', () async {
    final outcome = await clientA.pair(
      address: addressB(),
      onCode: (_) => serverB.rejectPendingPair(),
      retryInterval: const Duration(milliseconds: 10),
    );
    expect(outcome, PairOutcome.rejected);
    expect(await dbA.getPeer('device-b'), isNull);
    expect(await dbB.getPeer('device-a'), isNull);
  });

  test('对端一直不确认 → timedOut,不留半配对', () async {
    final outcome = await clientA.pair(
      address: addressB(),
      onCode: (_) {}, // B 侧用户什么也不点
      retryInterval: const Duration(milliseconds: 5),
      timeout: const Duration(milliseconds: 60),
    );
    expect(outcome, PairOutcome.timedOut);
    expect(await dbA.getPeer('device-b'), isNull);
    expect(await dbB.getPeer('device-a'), isNull);
  });

  test('地址不可达 → failed(不抛异常)', () async {
    final outcome = await clientA.pair(
      address: '127.0.0.1:1', // 没人监听
      onCode: (_) {},
      retryInterval: const Duration(milliseconds: 5),
      timeout: const Duration(milliseconds: 60),
    );
    expect(outcome, PairOutcome.failed);
  });

  test('解除配对后 hello 抛 unknown_device', () async {
    await clientA.pair(
      address: addressB(),
      onCode: (_) => serverB.acceptPendingPair(),
      retryInterval: const Duration(milliseconds: 10),
    );
    await dbB.deletePeer('device-a'); // B 侧解除
    // 异步抛出必须用 expectLater + Future,写成 expect(() => ...) 会让错误
    // 变成未捕获的异步异常,测试假过。
    await expectLater(
      clientA.hello(peerDeviceId: 'device-b'),
      throwsA(
        isA<SyncAuthException>().having(
          (e) => e.reason,
          'reason',
          'unknown_device',
        ),
      ),
    );
  });

  test('未配对就 hello → 抛 StateError', () async {
    await expectLater(
      clientA.hello(peerDeviceId: 'never-met'),
      throwsA(isA<StateError>()),
    );
  });
}
