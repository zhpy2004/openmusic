import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/sync_client.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';

void main() {
  // 两台"设备"各持独立内存库,不是 drift 警告所指的共享 executor 竞态。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase dbA;
  late AppDatabase dbB;
  late SyncServer serverA;
  late SyncServer serverB;
  late SyncClient clientA;

  Future<void> addTrack(AppDatabase db, String fp) => db.upsertTrack(
    TracksCompanion.insert(
      path: '/m/$fp.mp3',
      fingerprint: fp,
      title: fp,
      sizeBytes: 1,
      mtimeMs: 1,
    ),
  );

  setUp(() async {
    dbA = AppDatabase(testExecutor());
    dbB = AppDatabase(testExecutor());
    serverA = SyncServer(
      db: dbA,
      deviceId: 'device-a',
      deviceName: '台式机',
      platform: 'windows',
      trackCount: () async => 0,
    );
    serverB = SyncServer(
      db: dbB,
      deviceId: 'device-b',
      deviceName: '手机',
      platform: 'android',
      trackCount: () async => 0,
    );
    await serverA.start();
    await serverB.start();
    clientA = SyncClient(
      db: dbA,
      deviceId: 'device-a',
      deviceName: '台式机',
      platform: 'windows',
    );
    // 直接建立配对状态(配对流程本身由 M3-A 的测试覆盖)
    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    await dbA.upsertPeer(
      deviceId: 'device-b',
      deviceName: '手机',
      platform: 'android',
      sharedKey: key,
    );
    await dbB.upsertPeer(
      deviceId: 'device-a',
      deviceName: '台式机',
      platform: 'windows',
      sharedKey: key,
    );
    await dbA.recordPeerContact(
      'device-b',
      address: '127.0.0.1:${serverB.port}',
    );
  });

  tearDown(() async {
    clientA.close();
    await serverA.stop();
    await serverB.stop();
    await dbA.close();
    await dbB.close();
  });

  test('电脑建的歌单同步到手机', () async {
    await addTrack(dbA, 'fp-1');
    final uuid = await dbA.createPlaylist('开车');
    await dbA.addToPlaylist(uuid, 'fp-1');

    final summary = await clientA.syncMetadata(peerDeviceId: 'device-b');

    final onB = await dbB.watchPlaylists().first;
    expect(onB.single.name, '开车');
    expect((await dbB.watchPlaylistItems(uuid).first).single.fp, 'fp-1');
    expect(summary.playlists + summary.favorites + summary.playEvents, 0);
  });

  test('双方各加各的歌:同步后两边都有(裁决 1 的核心价值)', () async {
    await addTrack(dbA, 'fp-1');
    await addTrack(dbB, 'fp-2');
    final uuid = await dbA.createPlaylist('开车');
    await dbA.addToPlaylist(uuid, 'fp-1');
    await clientA.syncMetadata(peerDeviceId: 'device-b'); // 先让两端都有这个歌单
    await dbB.addToPlaylist(uuid, 'fp-2');

    await clientA.syncMetadata(peerDeviceId: 'device-b');

    final fpsOnA = (await dbA.watchPlaylistItems(uuid).first)
        .map((e) => e.fp)
        .toSet();
    final fpsOnB = (await dbB.watchPlaylistItems(uuid).first)
        .map((e) => e.fp)
        .toSet();
    expect(fpsOnA, {'fp-1', 'fp-2'});
    expect(fpsOnB, {'fp-1', 'fp-2'});

    // 额外断言(计划之外,按要求加):集合相等掩盖不了顺序错乱。
    // 02e35af 修的那个 position 撞号 bug 就是 ORDER BY position 顺序未定义。
    //
    // 第一轮同步是不对称的单向追加:A 把自己的快照发给 B,B 合并后把"B 合并后的"
    // 快照回给 A。A 本地已有 fp-1(position 0),对端 B 的 fp-2 是"仅对端有且未删",
    // 按 §4 的 position 规则会被追加到 A 本地末尾;而 B 那边是先把 A 的快照(只有
    // fp-1)合并进来,B 本地已有的 fp-2 保留原位,merge 结果顺序取决于两边各自
    // "追加对端新增项"的落点,此刻两端不保证一致。所以这里只按顺序打印/不做强断言,
    // 用于人工核对;真正的顺序收敛断言在下面"再同步一轮"之后。
    final orderedOnAAfterFirstRound = (await dbA.watchPlaylistItems(uuid).first)
        ..sort((a, b) => a.position.compareTo(b.position));
    final orderedOnBAfterFirstRound = (await dbB.watchPlaylistItems(uuid).first)
        ..sort((a, b) => a.position.compareTo(b.position));
    // ignore: avoid_print
    print(
      '第一轮后 A 顺序: ${orderedOnAAfterFirstRound.map((e) => e.fp).toList()}, '
      'B 顺序: ${orderedOnBAfterFirstRound.map((e) => e.fp).toList()}',
    );

    // 再同步一轮:这一轮里 A 把"已经包含 fp-1+fp-2"的快照发给 B,B 合并后把自己
    // 的（此刻也已收敛为同一顺序基础的）快照回给 A —— 两端此后各自的 position
    // 都来自同一份已经合并过的数据,不再各自独立追加,因此顺序收敛一致。
    await clientA.syncMetadata(peerDeviceId: 'device-b');

    final orderedFpsOnA = (await dbA.watchPlaylistItems(uuid).first)
        .map((e) => e.fp)
        .toList();
    final orderedFpsOnB = (await dbB.watchPlaylistItems(uuid).first)
        .map((e) => e.fp)
        .toList();
    expect(
      orderedFpsOnA,
      orderedFpsOnB,
      reason:
          '两轮同步后,两端按 position 排序的指纹序列必须完全一致(不只是集合相等)',
    );
  });

  test('删除会传播,再同步一次也不会复活', () async {
    await addTrack(dbA, 'fp-1');
    await dbA.toggleFavorite('fp-1');
    await clientA.syncMetadata(peerDeviceId: 'device-b');
    expect(await dbB.watchFavorites().first, ['fp-1']);

    await dbB.toggleFavorite('fp-1'); // 手机上取消收藏
    await clientA.syncMetadata(peerDeviceId: 'device-b');
    expect(await dbA.watchFavorites().first, isEmpty);

    await clientA.syncMetadata(peerDeviceId: 'device-b'); // 再来一轮
    expect(await dbA.watchFavorites().first, isEmpty); // 不复活
    expect(await dbB.watchFavorites().first, isEmpty);
  });

  test('播放记录取并集,反复同步不产生重复', () async {
    await addTrack(dbA, 'fp-1');
    await addTrack(dbB, 'fp-1');
    await dbA.logPlayEventAt('fp-1', 111);
    await dbB.logPlayEventAt('fp-1', 222);

    await clientA.syncMetadata(peerDeviceId: 'device-b');
    await clientA.syncMetadata(peerDeviceId: 'device-b');

    final onA = await dbA.readSyncSnapshot('device-a');
    final onB = await dbB.readSyncSnapshot('device-b');
    expect(onA.playEvents.length, 2);
    expect(onB.playEvents.length, 2);
  });

  test('摘要反映本地实际变更数', () async {
    await addTrack(dbB, 'fp-9');
    await dbB.toggleFavorite('fp-9');

    final summary = await clientA.syncMetadata(peerDeviceId: 'device-b');
    expect(summary.favorites, 1);

    final again = await clientA.syncMetadata(peerDeviceId: 'device-b');
    expect(again.isEmpty, isTrue); // 已是最新
  });

  test('对端没有该端点(老版本)→ 抛 SyncUnsupportedException', () async {
    await serverB.stop(); // 换一个不认这个路径的服务
    final legacy = SyncServer(
      db: dbB,
      deviceId: 'device-b',
      deviceName: '手机',
      platform: 'android',
      trackCount: () async => 0,
      enableMetadataSyncForTest: false,
    );
    await legacy.start();
    addTearDown(legacy.stop);
    await dbA.recordPeerContact(
      'device-b',
      address: '127.0.0.1:${legacy.port}',
    );

    await expectLater(
      clientA.syncMetadata(peerDeviceId: 'device-b'),
      throwsA(isA<SyncUnsupportedException>()),
    );
  });
}
