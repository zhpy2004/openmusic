import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/library/fingerprint.dart';
import 'package:openmusic/src/sync/sync_client.dart';
import 'package:openmusic/src/sync/sync_server.dart';

import 'helpers/db.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase dbA; // 拉文件的一方
  late AppDatabase dbB; // 有文件的一方
  late SyncServer serverB;
  late SyncClient clientA;
  late Directory tmp;
  late Directory destDir;

  setUp(() async {
    dbA = AppDatabase(testExecutor());
    dbB = AppDatabase(testExecutor());
    tmp = await Directory.systemTemp.createTemp('om-fsync');
    destDir = await Directory('${tmp.path}/dest').create();

    // B 上有两首歌(其中一首带封面)
    //
    // 注:内容按曲目序号(而非曲名长度)错开字节 —— 若沿用原计划里的
    // `name.length`,'歌一'/'歌二' 在 Dart 里 .length 都是 2(各一个 BMP
    // 码点),两份文件字节完全相同,导致内容指纹撞车。指纹一旦重复,
    // trackByFingerprint 的 getSingleOrNull() 命中两行就会抛异常,
    // 服务端对第二首返回 500,下载全灭 —— 这是计划测试数据本身的坑,
    // 不是被测代码的问题(已用调试用例定位到根因)。
    var trackSeed = 0;
    for (final name in const ['歌一', '歌二']) {
      trackSeed++;
      final f = File('${tmp.path}/$name.mp3');
      await f.writeAsBytes(List<int>.generate(200 * 1024, (i) => (i + trackSeed) % 256));
      final fp = await computeFileFingerprint(f);
      await dbB.upsertTrack(
        TracksCompanion.insert(
          path: f.path,
          fingerprint: fp,
          title: name,
          sizeBytes: await f.length(),
          mtimeMs: 1,
        ),
      );
      if (name == '歌一') {
        await File('${tmp.path}/$name.jpg').writeAsBytes([9, 9, 9]);
      }
    }

    const key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
    await dbA.upsertPeer(
      deviceId: 'device-b',
      deviceName: '台式机',
      platform: 'windows',
      sharedKey: key,
    );
    await dbB.upsertPeer(
      deviceId: 'device-a',
      deviceName: '手机',
      platform: 'android',
      sharedKey: key,
    );

    serverB = SyncServer(
      db: dbB,
      deviceId: 'device-b',
      deviceName: '台式机',
      platform: 'windows',
      trackCount: () async => 2,
    );
    await serverB.start();
    await dbA.recordPeerContact(
      'device-b',
      address: '127.0.0.1:${serverB.port}',
    );

    clientA = SyncClient(
      db: dbA,
      deviceId: 'device-a',
      deviceName: '手机',
      platform: 'android',
    );
  });

  tearDown(() async {
    clientA.close();
    await serverB.stop();
    await dbA.close();
    await dbB.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('拉清单:两首歌都在,封面标记正确', () async {
    final manifest = await clientA.fetchFileManifest(peerDeviceId: 'device-b');
    expect(manifest.length, 2);
    final withCover = manifest.where((f) => f.hasCover).toList();
    expect(withCover.single.name, '歌一.mp3');
  });

  test('按计划下载:文件落盘、指纹一致、封面一并到达', () async {
    final manifest = await clientA.fetchFileManifest(peerDeviceId: 'device-b');
    final result = await clientA.downloadFiles(
      peerDeviceId: 'device-b',
      files: manifest,
      destDir: destDir,
    );

    expect(result.downloaded, 2);
    expect(result.failed, 0);
    final names = destDir.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last).toSet();
    expect(names.contains('歌一.mp3'), isTrue);
    expect(names.contains('歌二.mp3'), isTrue);
    expect(names.contains('歌一.jpg'), isTrue); // sidecar 跟着来了

    // 落盘文件的指纹必须与对端一致
    final downloaded = File('${destDir.path}/歌一.mp3');
    final fpOnB = (await dbB.watchTracks('').first)
        .firstWhere((t) => t.title == '歌一')
        .fingerprint;
    expect(await computeFileFingerprint(downloaded), fpOnB);
  });

  test('传空列表:什么都不做(去重发生在 planFileSync,不在这一层)', () async {
    final manifest = await clientA.fetchFileManifest(peerDeviceId: 'device-b');
    await clientA.downloadFiles(
      peerDeviceId: 'device-b',
      files: manifest,
      destDir: destDir,
    );
    final before = destDir.listSync().length;

    // 第二次:文件名会撞,但内容相同 —— downloadFiles 不做去重判断,
    // 去重发生在 planFileSync(本机已有该指纹就不会进 files 列表)。
    // 这里验证的是"传空列表什么都不做"。
    final second = await clientA.downloadFiles(
      peerDeviceId: 'device-b',
      files: const [],
      destDir: destDir,
    );
    expect(second.downloaded, 0);
    expect(destDir.listSync().length, before);
  });

  test('取消后停止下载,已完成的保留', () async {
    final manifest = await clientA.fetchFileManifest(peerDeviceId: 'device-b');
    var started = 0;
    final result = await clientA.downloadFiles(
      peerDeviceId: 'device-b',
      files: manifest,
      destDir: destDir,
      onFileStart: (_, __, ___) => started++,
      shouldCancel: () => started > 1, // 第二首开始时取消
    );
    expect(result.cancelled, isTrue);
    expect(result.downloaded, lessThan(2));
  });

  test('对端是老版本(清单 404)→ 抛 SyncUnsupportedException', () async {
    await serverB.stop();
    final legacy = SyncServer(
      db: dbB,
      deviceId: 'device-b',
      deviceName: '台式机',
      platform: 'windows',
      trackCount: () async => 2,
      enableFileSyncForTest: false,
    );
    await legacy.start();
    addTearDown(legacy.stop);
    await dbA.recordPeerContact(
      'device-b',
      address: '127.0.0.1:${legacy.port}',
    );

    await expectLater(
      clientA.fetchFileManifest(peerDeviceId: 'device-b'),
      throwsA(isA<SyncUnsupportedException>()),
    );
  });
}
