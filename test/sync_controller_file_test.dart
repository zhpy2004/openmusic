import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/sync/sync_controller.dart';

import 'helpers/db.dart';
import 'helpers/fake_discovery.dart';

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
    );
  });

  tearDown(() async {
    controller.dispose();
    discovery.dispose();
    await db.close();
  });

  test('文件进度初始为空,开始后可读', () {
    expect(controller.fileProgress, isNull);
    controller.setFileProgressForTest(
      const FileSyncProgress(index: 2, total: 5, name: '及时雨.mp3'),
    );
    expect(controller.fileProgress!.index, 2);
    expect(controller.fileProgress!.name, '及时雨.mp3');
  });

  test('取消标志能被置起与清除', () {
    expect(controller.fileSyncCancelled, isFalse);
    controller.cancelFileSync();
    expect(controller.fileSyncCancelled, isTrue);
    controller.setFileProgressForTest(null);
    expect(controller.fileSyncCancelled, isFalse); // 清进度时一并复位
  });
}
