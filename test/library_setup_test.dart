import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/library/library_setup.dart';
import 'package:openmusic/src/library/scanner.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';

void main() {
  test('runLibraryScan:透传进度、结束清空进度(onProgress 末值 null)', () async {
    final db = AppDatabase(testExecutor());
    addTearDown(db.close);
    // 用真实空临时目录当根:扫描器正常收尾(0 文件),不抛异常。
    final dir = await Directory.systemTemp.createTemp('om_setup');
    addTearDown(() async => dir.delete(recursive: true));
    await db.addScanRoot(dir.path);

    final progresses = <ScanProgress?>[];
    final problems = <List<ScanProblem>>[];

    await runLibraryScan(
      db: db,
      scanner: LibraryScanner(db, FakeTagReader()),
      onProgress: progresses.add,
      onProblems: problems.add,
    );

    // 最后一次 onProgress 为 null(finally 清进度)。
    expect(progresses.isNotEmpty, true);
    expect(progresses.last, isNull);
    // onProblems 至少被调用一次(开扫清空)。
    expect(problems.isNotEmpty, true);
  });
}
