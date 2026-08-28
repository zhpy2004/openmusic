import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/sync_storage.dart';

import 'helpers/db.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(testExecutor());
    tmp = await Directory.systemTemp.createTemp('om-syncdir');
  });

  tearDown(() async {
    await db.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('目录不存在时会被创建,并登记为扫描根', () async {
    final target = Directory('${tmp.path}/OpenMusic/Synced');
    expect(await target.exists(), isFalse);

    final root = await ensureSyncRoot(db, resolveDir: () async => target);

    expect(await target.exists(), isTrue);
    expect(await db.watchScanRoots().first, contains(root));
  });

  test('重复调用幂等:不重复登记扫描根', () async {
    final target = Directory('${tmp.path}/OpenMusic/Synced');
    final root = await ensureSyncRoot(db, resolveDir: () async => target);
    await ensureSyncRoot(db, resolveDir: () async => target);

    final roots = await db.watchScanRoots().first;
    expect(roots.where((r) => r == root).length, 1);
  });

  test('用户手动删掉目录后再调用,会重新建出来', () async {
    final target = Directory('${tmp.path}/OpenMusic/Synced');
    await ensureSyncRoot(db, resolveDir: () async => target);
    await target.delete(recursive: true);

    await ensureSyncRoot(db, resolveDir: () async => target);
    expect(await target.exists(), isTrue);
  });
}
