import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openmusic/src/data/database.dart';
import 'package:openmusic/src/library/scanner.dart';

import 'helpers/db.dart';
import 'helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late FakeTagReader tags;
  late LibraryScanner scanner;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase(testExecutor());
    tags = FakeTagReader();
    scanner = LibraryScanner(db, tags);
    tmp = await Directory.systemTemp.createTemp('scan_test');
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  File write(String rel, [String content = 'x']) {
    final f = File('${tmp.path}/$rel')..createSync(recursive: true);
    f.writeAsStringSync(content);
    return f;
  }

  test('首扫：音频扩展名入库，其他文件忽略', () async {
    write('a.mp3');
    write('sub/b.flac');
    write('cover.jpg');
    await scanner.scan([tmp.path]).drain<void>();
    final all = await db.watchTracks('').first;
    expect(all.map((t) => t.title).toSet(), {'a.mp3', 'b.flac'});
  });

  test('增量：mtime+size 未变则不重读标签', () async {
    write('a.mp3');
    await scanner.scan([tmp.path]).drain<void>();
    tags.readPaths.clear();
    await scanner.scan([tmp.path]).drain<void>();
    expect(tags.readPaths, isEmpty);
  });

  test('增量：内容变了（size 变）会重读并更新', () async {
    write('a.mp3', 'short');
    await scanner.scan([tmp.path]).drain<void>();
    write('a.mp3', 'longer-content');
    tags.readPaths.clear();
    await scanner.scan([tmp.path]).drain<void>();
    expect(tags.readPaths.length, 1);
  });

  test('文件删除后，重扫会移除对应行', () async {
    final f = write('a.mp3');
    write('b.mp3');
    await scanner.scan([tmp.path]).drain<void>();
    f.deleteSync();
    await scanner.scan([tmp.path]).drain<void>();
    final all = await db.watchTracks('').first;
    expect(all.single.title, 'b.mp3');
  });

  test('损坏文件跳过并计入 problems，不中断扫描', () async {
    write('corrupt.mp3');
    write('ok.mp3');
    final events = await scanner.scan([tmp.path]).toList();
    final all = await db.watchTracks('').first;
    expect(all.single.title, 'ok.mp3');
    expect(events.last.problems, hasLength(1));
    final problem = events.last.problems.single;
    expect(problem, isA<FileFailed>());
    expect((problem as FileFailed).path, contains('corrupt.mp3'));
  });

  test('进度流：scanned 递增到 total', () async {
    write('a.mp3');
    write('b.mp3');
    final events = await scanner.scan([tmp.path]).toList();
    expect(events.last.scanned, events.last.total);
    expect(events.last.total, 2);
  });

  test('超过 200 文件触发批量 flush 且全部入库', () async {
    for (var i = 0; i < 250; i++) {
      write('t$i.mp3');
    }
    await scanner.scan([tmp.path]).drain<void>();
    final all = await db.watchTracks('').first;
    expect(all.length, 250);
  });

  test('root 不存在：正常完成、0 曲目、不抛', () async {
    final events = await scanner.scan(['${tmp.path}/no_such_dir']).toList();
    final all = await db.watchTracks('').first;
    expect(all, isEmpty);
    expect(events.last.done, isTrue);
  });

  test('大写扩展名（t.MP3）也入库', () async {
    write('t.MP3');
    await scanner.scan([tmp.path]).drain<void>();
    final all = await db.watchTracks('').first;
    expect(all.single.title, 't.MP3');
  });

  test('多 root：两个独立目录各自文件全入库', () async {
    write('a.mp3');
    final tmp2 = await Directory.systemTemp.createTemp('scan_test2');
    addTearDown(() => tmp2.delete(recursive: true));
    File('${tmp2.path}/b.mp3').writeAsStringSync('x');
    await scanner.scan([tmp.path, tmp2.path]).drain<void>();
    final all = await db.watchTracks('').first;
    expect(all.map((t) => t.title).toSet(), {'a.mp3', 'b.mp3'});
  });

  test('重叠 root：sub 下文件只读一次 tag 且 total 不虚高', () async {
    write('sub/a.mp3');
    final events = await scanner.scan([tmp.path, '${tmp.path}/sub']).toList();
    expect(tags.readPaths.length, 1);
    expect(events.last.total, 1);
    final all = await db.watchTracks('').first;
    expect(all.single.title, 'a.mp3');
  });

  test('增量重扫进度：250 文件全跳过时进度流仍周期上报', () async {
    for (var i = 0; i < 250; i++) {
      write('t$i.mp3');
    }
    await scanner.scan([tmp.path]).drain<void>();
    tags.readPaths.clear();
    final events = await scanner.scan([tmp.path]).toList();
    expect(tags.readPaths, isEmpty); // 全部走 skip 路径
    expect(events.length, greaterThanOrEqualTo(2)); // 周期 yield + done
    expect(events.last.scanned, 250);
    expect(events.last.total, 250);
  });

  test('root 不可达（如 NAS/SD 卡离线）：保留其下已入库曲目、记入 problems，'
      '可达 root 的增删仍正常', () async {
    final tmpB = await Directory.systemTemp.createTemp('scan_testB');
    var tmpBAlive = true;
    addTearDown(() {
      if (tmpBAlive) tmpB.deleteSync(recursive: true);
    });

    final a = write('a.mp3');
    File('${tmpB.path}/b.mp3').writeAsStringSync('x');
    // 首扫：A、B 均可达，两曲目都入库。
    await scanner.scan([tmp.path, tmpB.path]).drain<void>();
    var all = await db.watchTracks('').first;
    expect(all.map((t) => t.title).toSet(), {'a.mp3', 'b.mp3'});

    // A 下删掉 a.mp3（验证可达 root 的正常清理不受影响）。
    a.deleteSync();
    // B 整个不可达（如 NAS 离线/未挂载）：目录本身消失，existsSync() 为 false。
    tmpB.deleteSync(recursive: true);
    tmpBAlive = false;

    final events = await scanner.scan([tmp.path, tmpB.path]).toList();

    all = await db.watchTracks('').first;
    // b.mp3 保留（不可达 root 不清理），a.mp3 已被清出（可达 root 正常清理）。
    expect(all.map((t) => t.title).toSet(), {'b.mp3'});
    // 问题是类型化对象(不含文案,渲染语言由 UI 层决定),断言类型与路径。
    expect(
      events.last.problems.any(
        (p) => p is RootUnreachable && p.path == tmpB.path,
      ),
      isTrue,
      reason: 'problems 应包含不可达根: ${events.last.problems}',
    );
  });

  test('root 从 roots 列表移除（非不可达，用户在设置里删掉了该根）：'
      '其曲目仍会被清理——保持既有语义', () async {
    final tmpB = await Directory.systemTemp.createTemp('scan_testB');
    addTearDown(() => tmpB.delete(recursive: true));

    write('a.mp3');
    File('${tmpB.path}/b.mp3').writeAsStringSync('x');
    await scanner.scan([tmp.path, tmpB.path]).drain<void>();
    var all = await db.watchTracks('').first;
    expect(all.map((t) => t.title).toSet(), {'a.mp3', 'b.mp3'});

    // 用户从设置移除了 B 根：本轮 scan 根本不传 tmpB.path（B 目录本身仍存在于磁盘）。
    await scanner.scan([tmp.path]).drain<void>();
    all = await db.watchTracks('').first;
    expect(all.map((t) => t.title).toSet(), {'a.mp3'});
  });

  test('重扫后文本修正仍生效(override 被重新叠加)', () async {
    write('a.mp3', 'short');
    await scanner.scan([tmp.path]).drain<void>();
    final before = await db.watchTracks('').first;
    final fp = before.single.fingerprint;

    await db.setTrackOverride(fp, title: '修正后的标题');
    var all = await db.watchTracks('').first;
    expect(all.single.title, '修正后的标题');

    // 只改 mtime（内容/size 不变，指纹也就不变）迫使重扫认为文件已变，
    // 从而重读标签写回 tracks——这才是测试"override 被重新叠加"而非
    // "指纹变了导致 override 对不上号"的正确姿势。
    final f = File('${tmp.path}/a.mp3');
    f.setLastModifiedSync(
      f.lastModifiedSync().add(const Duration(seconds: 5)),
    );
    await scanner.scan([tmp.path]).drain<void>();

    all = await db.watchTracks('').first;
    expect(all.single.title, '修正后的标题');
  });
}
